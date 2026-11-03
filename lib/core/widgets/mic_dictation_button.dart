import 'dart:async';
import 'dart:io';
import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../services/whisper_service.dart';
import '../theme/app_colors.dart';

/// One-time onboarding-hint flags (persisted across launches). Users often
/// press-and-hold the mic like a walkie-talkie; we explain tap/tap once.
const String _kHoldHintShownKey = 'mic_dictation_hold_hint_shown';
const String _kStopHintShownKey = 'mic_dictation_stop_hint_shown';

enum MicPhase { idle, recording, transcribing }

/// Mic recording + offline Whisper transcription lifecycle for one field.
class MicDictationController extends ChangeNotifier {
  final _recorder = AudioRecorder();
  Timer? _pulseTimer;
  bool _disposed = false;

  MicPhase phase = MicPhase.idle;
  bool pulseOn = false;

  /// Fired once with the transcribed text.
  void Function(String text)? onResult;

  /// Fired once with a user-facing error message.
  void Function(String message)? onError;

  /// Fired when a recording starts.
  VoidCallback? onRecordingStarted;

  void _set({MicPhase? phase, bool? pulseOn}) {
    this.phase = phase ?? this.phase;
    this.pulseOn = pulseOn ?? this.pulseOn;
    if (!_disposed) notifyListeners();
  }

  Future<void> toggle() async {
    switch (phase) {
      case MicPhase.idle:
        await _start();
      case MicPhase.recording:
        await _stopAndTranscribe();
      case MicPhase.transcribing:
        break; // ignore taps while transcribing
    }
  }

  Future<void> _start() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      onError?.call('Microphone permission denied');
      return;
    }

    final tmp = await getTemporaryDirectory();
    final path =
        '${tmp.path}/dictation_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    _set(phase: MicPhase.recording, pulseOn: true);
    onRecordingStarted?.call();
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(
      const Duration(milliseconds: 425),
      (_) => _set(pulseOn: !pulseOn),
    );
  }

  Future<void> _stopAndTranscribe() async {
    _pulseTimer?.cancel();
    _pulseTimer = null;

    final path = await _recorder.stop();
    if (path == null || path.isEmpty) {
      _set(phase: MicPhase.idle, pulseOn: false);
      onError?.call('Recording failed — no audio captured');
      return;
    }

    _set(phase: MicPhase.transcribing, pulseOn: false);
    if (kDebugMode) {
      final bytes = File(path).readAsBytesSync();
      var peak = 0;
      var clipped = 0;
      var sumSq = 0.0;
      var n = 0;
      for (var i = 44; i + 1 < bytes.length; i += 2) {
        var v = bytes[i] | (bytes[i + 1] << 8);
        if (v > 32767) v -= 65536;
        final a = v.abs();
        if (a > peak) peak = a;
        if (a >= 32000) clipped++;
        sumSq += v * v;
        n++;
      }
      final rms = n == 0 ? 0 : sqrt(sumSq / n).round();
      debugPrint('[dictation] recorded ${bytes.length} bytes, peak $peak, '
          'rms $rms, clipped samples $clipped/$n (peak ~0 = silence, '
          'many clipped = mic gain too high)');
    }

    try {
      final modelPath = await whisperModelPath();
      final whisper = Whisper(
        model: WhisperModel.baseEn,
        modelDir: modelPath.replaceAll('/ggml-base.en.bin', ''),
      );
      final response = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: path,
          language: 'en',
          isNoTimestamps: true,
          suppressNonSpeechTokens: true,
        ),
        modelPath: modelPath,
      );

      debugPrint('[dictation] whisper raw text: "${response.text}"');
      final text = response.text.trim();
      _set(phase: MicPhase.idle);
      if (text.isEmpty) {
        onError?.call("Couldn't understand — try speaking clearly");
      } else {
        onResult?.call(text);
      }
    } catch (e) {
      _set(phase: MicPhase.idle);
      onError?.call('Transcription error: $e');
    } finally {
      unawaited(() async {
        try {
          // whisper_ggml writes a converted copy next to the recording.
          for (final f in [File(path), File('$path.wav')]) {
            if (f.existsSync()) await f.delete();
          }
        } catch (_) {}
      }());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pulseTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}

/// Icon-only button that records the mic and transcribes it offline via the
/// bundled Whisper model, then hands the text back through [onTranscribed].
/// Adds no container/border, so it drops into a field's trailing-icon slot.
class MicDictationButton extends StatefulWidget {
  const MicDictationButton({
    super.key,
    required this.onTranscribed,
    this.iconSize = 20,
    this.idleColor,
  });

  final ValueChanged<String> onTranscribed;
  final double iconSize;
  final Color? idleColor;

  @override
  State<MicDictationButton> createState() => _MicDictationButtonState();
}

class _MicDictationButtonState extends State<MicDictationButton> {
  final _controller = MicDictationController();

  @override
  void initState() {
    super.initState();
    _controller.onResult = (t) => widget.onTranscribed(t);
    _controller.onError = _showSnack;
    _controller.onRecordingStarted = _maybeShowStopHint;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _controller.toggle,
      // A hold is a misuse in the tap-to-toggle model — coach instead.
      onLongPress: _handleHold,
      child: SizedBox(
        width: widget.iconSize + 8,
        height: widget.iconSize + 8,
        child: Center(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (_, _) => _buildIcon(),
          ),
        ),
      ),
    );
  }

  Future<void> _handleHold() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_kHoldHintShownKey) ?? false;
    if (!mounted) return;

    if (seen) {
      _showSnack('Tap once to start, tap again to stop — no need to hold.');
      return;
    }
    await prefs.setBool(_kHoldHintShownKey, true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'No need to hold',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.navy,
            fontSize: 16,
          ),
        ),
        content: const Text(
          "Just tap the mic once to start recording, then tap it again to "
          "stop. You don't have to hold the button down.",
          style: TextStyle(color: AppColors.text, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Got it',
              style: TextStyle(
                color: AppColors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _maybeShowStopHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kStopHintShownKey) ?? false) return;
    await prefs.setBool(_kStopHintShownKey, true);
    _showSnack("Recording started — tap the mic again when you're done.");
  }

  Widget _buildIcon() {
    final size = widget.iconSize;
    switch (_controller.phase) {
      case MicPhase.transcribing:
        return SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.orange),
          ),
        );
      case MicPhase.recording:
        return AnimatedOpacity(
          opacity: _controller.pulseOn ? 1 : 0.35,
          duration: const Duration(milliseconds: 425),
          child: Icon(Icons.stop_rounded, size: size, color: AppColors.red),
        );
      case MicPhase.idle:
        return Icon(
          Icons.mic_none_rounded,
          size: size,
          color: widget.idleColor ?? AppColors.muted,
        );
    }
  }
}
