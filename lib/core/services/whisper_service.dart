import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

const String _kWhisperModelAsset = 'assets/models/ggml-base.en.bin';
const String _kWhisperModelFileName = 'ggml-base.en.bin';

Future<String>? _modelPath;

/// Resolves the on-device path to the bundled Whisper model, copying it from
/// the app bundle to the documents directory on first run (whisper_ggml needs
/// a real filesystem path, not a Flutter asset URI). Cached for the lifetime
/// of the app so every mic button reuses the same copy.
Future<String> whisperModelPath() => _modelPath ??= _resolve();

Future<String> _resolve() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/$_kWhisperModelFileName');
    if (!dest.existsSync()) {
      final data = await rootBundle.load(_kWhisperModelAsset);
      await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return dest.path;
  } catch (_) {
    _modelPath = null; // allow retry after a failed copy
    rethrow;
  }
}
