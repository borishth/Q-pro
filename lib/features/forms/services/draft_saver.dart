import 'dart:async';

import '../../../core/network/infrive_api.dart';

/// Batches answer edits for one draft submission and sends them as a single
/// `saveSubmission` call after 800ms of inactivity, so typing doesn't fire a
/// request per keystroke. A failed flush keeps the unsent values queued.
class DraftSaver {
  DraftSaver(this._api, this.formId, this.submissionName);

  final InfriveApi _api;
  final String formId;
  final String submissionName;

  final Map<String, dynamic> _pending = {};
  Timer? _timer;

  void change(String questionId, dynamic value) {
    _pending[questionId] = value;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), flush);
  }

  Future<void> flush() async {
    if (_pending.isEmpty) return;
    final batch = Map<String, dynamic>.from(_pending);
    _pending.clear();
    try {
      await _api.saveSubmission(
        form: formId,
        submission: submissionName,
        answers: batch,
      );
    } catch (_) {
      _pending.addAll({...batch, ..._pending});
    }
  }

  void dispose() => _timer?.cancel();
}
