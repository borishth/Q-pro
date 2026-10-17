import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/permissions.dart';
import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/storage/outbox_db.dart';
import '../../../core/storage/outbox_sync.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_nav_bar.dart';
import '../../../core/widgets/scale_button.dart';
import '../models/field_behaviour.dart';
import '../models/form_payload.dart';
import '../models/question.dart';
import '../models/submission_detail.dart';
import '../services/draft_saver.dart';
import 'link_picker_page.dart';
import 'signature_capture_page.dart';

String _pad4(int n) => n.toString().padLeft(4, '0');
String _pad2(int n) => n.toString().padLeft(2, '0');

/// Private file URLs come back as `/private/files/...`; join them with the
/// base URL and load with `sdk.api.requestHeaders` so the auth header rides
/// along (see the Flutter API Guide section 8).
String _absoluteFileUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = sdk.baseUrl.endsWith('/')
      ? sdk.baseUrl.substring(0, sdk.baseUrl.length - 1)
      : sdk.baseUrl;
  final path = url.startsWith('/') ? url : '/$url';
  return '$base$path';
}

/// Field-type badge shown in each question's header — purely cosmetic,
/// same spirit as the ConstructionHub design's field-type pills.
(String, String) _fieldMeta(Question question, String link) {
  if (link.isNotEmpty) return ('🔗', 'LINK');
  return switch (question.type) {
    'text' => ('📝', 'TEXT'),
    'textarea' => ('📝', 'TEXT'),
    'number' => ('🔢', 'NUMBER'),
    'currency' => ('💰', 'CURRENCY'),
    'rating' => ('⭐', 'RATING'),
    'date' => ('📅', 'DATE'),
    'datetime' => ('📅', 'DATETIME'),
    'yes_no' => ('☑️', 'YES/NO'),
    'checkbox' => ('☑️', 'CHECKBOX'),
    'select' => ('▾', 'SELECT'),
    'radio' => ('◉', 'RADIO'),
    'multi_select' => ('▾', 'MULTI'),
    'table' => ('📋', 'TABLE'),
    'file' => ('📎', 'FILE'),
    'image' => ('🖼️', 'IMAGE'),
    'signature' => ('✒️', 'SIGNATURE'),
    _ => ('📝', 'TEXT'),
  };
}

bool _isAnswered(dynamic value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is List) return value.isNotEmpty;
  return true;
}

// ---------------- FORM FILL SCREEN ----------------

class FormFillPage extends StatefulWidget {
  final String? formId;
  final String? stageId;
  final String? formTitle;
  final String? resumeLocalId;

  const FormFillPage({
    super.key,
    required this.formId,
    required this.stageId,
    required this.formTitle,
  }) : resumeLocalId = null;

  /// Reopens an existing local draft (from the Drafts screen) for editing
  /// — whether it's merely queued or stuck in `attention` — instead of
  /// starting a brand new one.
  const FormFillPage.resume({super.key, required this.resumeLocalId})
      : formId = null,
        stageId = null,
        formTitle = null;

  @override
  State<FormFillPage> createState() => _FormFillPageState();
}

class _FormFillPageState extends State<FormFillPage> {
  bool isLoading = true;
  bool isSubmitting = false;
  String? errorMessage;
  SubmissionDetail? submission;
  final Map<String, dynamic> answers = {};
  final Map<String, bool> uploading = {};
  final Map<String, String> pendingUploadPaths = {};
  final ImagePicker _imagePicker = ImagePicker();
  DraftSaver? saver;

  /// True once this page is working against a local draft row rather than
  /// calling the server directly — either because no connection was
  /// available when it was created, or because it was reopened from the
  /// Drafts screen for editing.
  bool isLocalDraft = false;

  /// True once a background sync finishes this exact draft (its `submit`
  /// job completed) while this screen was still open — further edits are
  /// blocked so the user can't queue a second submit on an already-done
  /// draft (see `_reconcileWithBackgroundSync`).
  bool backgroundSynced = false;

  @override
  void initState() {
    super.initState();
    isOnline.addListener(_handleConnectivityChange);
    OutboxSync.instance.pendingCount.addListener(_handleQueueChange);
    final resumeId = widget.resumeLocalId;
    if (resumeId != null) {
      _resumeDraft(resumeId);
    } else {
      createDraft();
    }
  }

  @override
  void dispose() {
    isOnline.removeListener(_handleConnectivityChange);
    OutboxSync.instance.pendingCount.removeListener(_handleQueueChange);
    saver?.flush();
    saver?.dispose();
    super.dispose();
  }

  void _handleConnectivityChange() {
    if (mounted) setState(() {});
  }

  void _handleQueueChange() {
    unawaited(_reconcileWithBackgroundSync());
  }

  /// A background sync can finish work on *this* draft while this screen
  /// is still open — most importantly, an upload completing. Without
  /// this, the screen's in-memory `answers` never learns the real file
  /// URL the queue wrote to the database, so hitting Submit afterwards
  /// would push the old, URL-less answers and silently drop the photo.
  /// Only the specific fields the queue actually finished are pulled in —
  /// never the whole answers map — so a field the user is mid-typing in
  /// right now is never clobbered by a stale background snapshot of it.
  Future<void> _reconcileWithBackgroundSync() async {
    final current = submission;
    if (current == null || !isLocalDraft || !mounted) return;

    final draft = await OutboxDatabase.instance.getDraft(current.name);
    if (draft == null || !mounted) return;

    if (draft['state'] == 'synced') {
      if (!backgroundSynced) {
        setState(() => backgroundSynced = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This draft finished syncing in the background."),
          ),
        );
      }
      return;
    }

    final stillPendingUploads =
        await OutboxDatabase.instance.pendingUploadsForDraft(current.name);
    if (!mounted) return;

    final completedQuestionIds = pendingUploadPaths.keys
        .where((questionId) => !stillPendingUploads.containsKey(questionId))
        .toList();
    if (completedQuestionIds.isEmpty) return;

    final syncedAnswers =
        jsonDecode(draft['answers_json'] as String) as Map<String, dynamic>;

    setState(() {
      for (final questionId in completedQuestionIds) {
        pendingUploadPaths.remove(questionId);
        if (syncedAnswers.containsKey(questionId)) {
          answers[questionId] = syncedAnswers[questionId];
        }
      }
    });
  }

  Future<void> createDraft() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    if (isOnline.value) {
      try {
        final draft = await infrive.saveSubmission(
          form: widget.formId!,
          stage: widget.stageId,
        );
        await _cacheFormPayload(draft.form);
        // Mirror it locally too (local_id == server name here) so a
        // queued upload or a mid-session connectivity drop always has a
        // drafts row to attach to.
        await OutboxDatabase.instance.insertDraft(
          localId: draft.name,
          serverName: draft.name,
          form: widget.formId!,
          stage: widget.stageId,
          answers: draft.answers,
        );

        if (!mounted) return;

        setState(() {
          submission = draft;
          answers.addAll(draft.answers);
          isLocalDraft = false;
          isLoading = false;
        });
        saver = DraftSaver(infrive, widget.formId!, draft.name);
        return;
      } catch (error) {
        if (error is! NetworkException) {
          if (!mounted) return;
          if (isSessionExpired(error)) {
            signOutToLogin(context);
            return;
          }

          setState(() {
            errorMessage = describeError(error);
            isLoading = false;
          });
          return;
        }
        // Lost connection mid-request: fall through to the offline path.
      }
    }

    await _createOfflineDraft();
  }

  Future<void> _cacheFormPayload(FormPayload form) {
    return OutboxDatabase.instance.cachePut('form:${widget.formId!}', {
      'id': form.id,
      'title': form.title,
      'version': form.version,
      'questions': [
        for (final q in form.questions)
          {
            'id': q.id,
            'type': q.type,
            'label': q.label,
            'required': q.required,
            'options': q.options,
            'help': q.help,
            'rule': q.rule,
            'parent': q.parent,
            'default': q.defaultValue,
          },
      ],
    });
  }

  Future<void> _createOfflineDraft() async {
    final cached =
        await OutboxDatabase.instance.cacheGet('form:${widget.formId!}');
    if (!mounted) return;

    if (cached == null) {
      setState(() {
        errorMessage =
            "This form hasn't been opened online yet, so it can't be "
            'filled offline. Connect and try again.';
        isLoading = false;
      });
      return;
    }

    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    await OutboxDatabase.instance.insertDraft(
      localId: localId,
      form: widget.formId!,
      stage: widget.stageId,
      answers: const {},
    );
    await OutboxDatabase.instance.enqueueIfAbsent('save', localId);
    OutboxSync.instance.wake();

    if (!mounted) return;
    setState(() {
      isLocalDraft = true;
      submission = SubmissionDetail(
        name: localId,
        status: 'Draft',
        project: '',
        stage: widget.stageId ?? '',
        form: FormPayload.fromJson(cached as Map<String, dynamic>),
        answers: const {},
        editable: true,
        permissions: Permissions.none,
        transitions: const [],
        history: const [],
      );
      isLoading = false;
    });
  }

  /// Reopens a draft the Drafts screen listed (queued or `attention`) so
  /// the user can change something before it's tried again. Clears any
  /// `attention` state up front — resuming to edit is how the user
  /// addresses whatever caused it — and restores both the saved answers
  /// and any photo/signature/file still waiting to upload.
  Future<void> _resumeDraft(String localId) async {
    final draft = await OutboxDatabase.instance.getDraft(localId);
    if (!mounted) return;

    if (draft == null) {
      setState(() {
        errorMessage = "This draft isn't available anymore.";
        isLoading = false;
      });
      return;
    }

    final formId = draft['form'] as String;
    final cached = await OutboxDatabase.instance.cacheGet('form:$formId');
    final pendingUploads =
        await OutboxDatabase.instance.pendingUploadsForDraft(localId);
    if (!mounted) return;

    if (cached == null) {
      setState(() {
        errorMessage = "This form's questions aren't cached anymore, so "
            "it can't be edited here.";
        isLoading = false;
      });
      return;
    }

    if (draft['state'] == 'attention') {
      await OutboxDatabase.instance.setDraftState(
        localId,
        draft['server_name'] == null ? 'local' : 'syncing',
      );
    }

    final savedAnswers =
        jsonDecode(draft['answers_json'] as String) as Map<String, dynamic>;

    setState(() {
      isLocalDraft = true;
      submission = SubmissionDetail(
        name: localId,
        status: 'Draft',
        project: '',
        stage: (draft['stage'] as String?) ?? '',
        form: FormPayload.fromJson(cached as Map<String, dynamic>),
        answers: savedAnswers,
        editable: true,
        permissions: Permissions.none,
        transitions: const [],
        history: const [],
      );
      answers
        ..clear()
        ..addAll(savedAnswers);
      pendingUploadPaths.addAll(pendingUploads);
      isLoading = false;
    });
  }

  void updateAnswer(String questionId, dynamic value) {
    setState(() {
      answers[questionId] = value;
    });

    final current = submission;
    if (current == null) return;

    if (isLocalDraft) {
      OutboxDatabase.instance.updateDraftAnswers(current.name, answers);
      OutboxDatabase.instance.enqueueIfAbsent('save', current.name);
      OutboxSync.instance.wake();
    } else {
      saver?.change(questionId, value);
    }
  }

  Future<void> pickImage(Question question, ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;
    await uploadFileAnswer(question, File(picked.path));
  }

  Future<void> pickGenericFile(Question question) async {
    final result = await FilePicker.pickFiles();
    final files = result?.files ?? const [];
    final path = files.isEmpty ? null : files.first.path;
    if (path == null || !mounted) return;
    await uploadFileAnswer(question, File(path));
  }

  Future<void> captureSignature(Question question) async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => const SignatureCapturePage(),
        fullscreenDialog: true,
      ),
    );
    if (bytes == null || !mounted) return;

    final file = await File(
      '${Directory.systemTemp.path}/signature_${DateTime.now().millisecondsSinceEpoch}.png',
    ).writeAsBytes(bytes);
    await uploadFileAnswer(question, file);
  }

  Future<void> uploadFileAnswer(Question question, File file) async {
    final current = submission;
    if (current == null) return;

    // Picking is always local — only the actual upload needs the network
    // and a draft the server already knows about. Otherwise queue it.
    if (!isOnline.value || isLocalDraft) {
      setState(() => pendingUploadPaths[question.id] = file.path);
      await OutboxDatabase.instance.enqueueUpload(
        current.name,
        question.id,
        file.path,
      );
      OutboxSync.instance.wake();
      return;
    }

    setState(() => uploading[question.id] = true);

    try {
      final uploaded = await sdk.api.attachment.uploadFile(
        file,
        doctype: 'Form Submission',
        docname: current.name,
      );
      final url = uploaded['file_url']?.toString();
      if (url == null || url.isEmpty) {
        throw Exception('Upload did not return a file URL.');
      }

      unawaited(file.delete().catchError((_) => file));

      if (!mounted) return;
      updateAnswer(question.id, url);
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        signOutToLogin(context);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: ${describeError(error)}')),
      );
    } finally {
      if (mounted) setState(() => uploading[question.id] = false);
    }
  }

  Future<void> submit() async {
    final current = submission;
    if (current == null) return;

    if (isLocalDraft) {
      setState(() => isSubmitting = true);
      await OutboxDatabase.instance.updateDraftAnswers(current.name, answers);
      await OutboxDatabase.instance.enqueueIfAbsent('submit', current.name);
      OutboxSync.instance.wake();

      if (!mounted) return;
      setState(() => isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Saved offline — it'll submit once you're back online."),
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    await saver?.flush();

    setState(() {
      isSubmitting = true;
    });

    try {
      await infrive.submit(current.name, answers: answers);
      await OutboxDatabase.instance.setDraftState(current.name, 'synced');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitted.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      if (isSessionExpired(error)) {
        signOutToLogin(context);
        return;
      }

      setState(() {
        isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeError(error))),
      );
    }
  }

  Future<void> _confirmAndSubmit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.assignment_turned_in_rounded,
                  color: AppColors.orange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Submit this form?',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Once submitted, this will be sent for review and the answers above will be locked.',
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ScaleButton(
                      onTap: () => Navigator.pop(ctx, false),
                      scaleBound: 0.95,
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.light,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Keep Editing',
                          style: GoogleFonts.sora(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ScaleButton(
                      onTap: () => Navigator.pop(ctx, true),
                      scaleBound: 0.95,
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Submit',
                          style: GoogleFonts.sora(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    await submit();
  }

  List<Question> _visibleQuestions(SubmissionDetail current) {
    final result = <Question>[];
    for (final q in current.form.questions) {
      final behaviour = FieldBehaviour.parse(q.rule);
      if (behaviour.hidden) continue;
      if (behaviour.dependsOn.isNotEmpty && !dependsMet(behaviour.dependsOn, answers)) {
        continue;
      }
      result.add(q);
    }
    return result;
  }

  Widget _unsupportedField(String reason) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.block, size: 16, color: AppColors.slate),
          const SizedBox(width: 8),
          Expanded(
            child: Text(reason, style: GoogleFonts.sora(fontSize: 12, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }

  Widget _linkField(Question question, String? value, bool enabled, String linkFormId) {
    final current = submission;
    final canPick = enabled && isOnline.value;
    final hasValue = value != null && value.isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: canPick
          ? () async {
              final project = current != null && current.project.isNotEmpty
                  ? current.project
                  : null;
              final picked = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => LinkPickerPage(formId: linkFormId, project: project),
                  fullscreenDialog: true,
                ),
              );
              if (picked != null) updateAnswer(question.id, picked);
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.link, color: AppColors.navy, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasValue
                    ? value
                    : canPick
                        ? 'Tap to select'
                        : 'Needs an internet connection',
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                  color: hasValue ? AppColors.text : AppColors.muted,
                ),
              ),
            ),
            if (canPick)
              const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.navy),
          ],
        ),
      ),
    );
  }

  Widget _filePreview(Question question, String? url, IconData placeholderIcon) {
    final pendingPath = pendingUploadPaths[question.id];

    Widget content;
    if (pendingPath != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(File(pendingPath), fit: BoxFit.contain),
      );
    } else if (url != null && url.isNotEmpty) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          _absoluteFileUrl(url),
          headers: sdk.api.requestHeaders,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image_outlined, size: 40, color: AppColors.slate),
        ),
      );
    } else {
      content = Icon(placeholderIcon, size: 40, color: AppColors.slate);
    }

    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.light,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: content,
    );
  }

  /// Picking a photo/signature is always local, so the buttons stay
  /// enabled offline too — only whether the bytes go straight to the
  /// server or get queued changes (see `uploadFileAnswer`).
  Widget _queuedUploadNote(Question question) {
    if (pendingUploadPaths[question.id] == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        "Will upload when you're back online.",
        style: GoogleFonts.sora(fontSize: 11, color: AppColors.orange, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _imageField(Question question, String? url, bool enabled) {
    final isUploading = uploading[question.id] ?? false;
    final hasFile = pendingUploadPaths[question.id] != null ||
        (url != null && url.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filePreview(question, url, Icons.image_outlined),
        _queuedUploadNote(question),
        const SizedBox(height: 10),
        if (isUploading)
          const LinearProgressIndicator(color: AppColors.orange, backgroundColor: AppColors.light)
        else if (enabled)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => pickImage(question, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 16),
                label: const Text('Camera'),
              ),
              OutlinedButton.icon(
                onPressed: () => pickImage(question, ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: Text(hasFile ? 'Replace' : 'Gallery'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _signatureField(Question question, String? url, bool enabled) {
    final isUploading = uploading[question.id] ?? false;
    final hasFile = pendingUploadPaths[question.id] != null ||
        (url != null && url.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filePreview(question, url, Icons.draw_outlined),
        _queuedUploadNote(question),
        const SizedBox(height: 10),
        if (isUploading)
          const LinearProgressIndicator(color: AppColors.orange, backgroundColor: AppColors.light)
        else if (enabled)
          OutlinedButton.icon(
            onPressed: () => captureSignature(question),
            icon: const Icon(Icons.draw_outlined, size: 16),
            label: Text(hasFile ? 'Redo signature' : 'Add signature'),
          ),
      ],
    );
  }

  Widget _fileField(Question question, String? url, bool enabled) {
    final isUploading = uploading[question.id] ?? false;
    final pendingPath = pendingUploadPaths[question.id];
    final fileName = pendingPath != null
        ? pendingPath.split('/').last
        : (url != null && url.isNotEmpty ? url.split('/').last : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.light,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.attach_file, color: AppColors.navy, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fileName ?? 'No file attached',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    color: fileName != null ? AppColors.text : AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        _queuedUploadNote(question),
        const SizedBox(height: 10),
        if (isUploading)
          const LinearProgressIndicator(color: AppColors.orange, backgroundColor: AppColors.light)
        else if (enabled)
          OutlinedButton.icon(
            onPressed: () => pickGenericFile(question),
            icon: const Icon(Icons.attach_file, size: 16),
            label: Text(fileName != null ? 'Replace file' : 'Choose file'),
          ),
      ],
    );
  }

  /// The guide doesn't specify a table question's column schema beyond
  /// the answer type (`List<Map<String, dynamic>>`), so this reuses
  /// `question.options` as the column names — the same field already
  /// used for select/radio/multi_select — and stores one string value
  /// per column per row.
  Widget _tableField(Question question, dynamic value, bool enabled) {
    final rows = value is List
        ? value.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    final columns = question.options;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (columns.isEmpty)
          _unsupportedField('This table has no columns configured.')
        else ...[
          for (var i = 0; i < rows.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.light,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Row ${i + 1}',
                          style: GoogleFonts.sora(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      if (enabled)
                        GestureDetector(
                          onTap: () {
                            final updated =
                                List<Map<String, dynamic>>.from(rows)..removeAt(i);
                            updateAnswer(question.id, updated);
                          },
                          child: const Icon(Icons.delete_outline, size: 18, color: AppColors.red),
                        ),
                    ],
                  ),
                  for (final column in columns)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: TextFormField(
                          key: ValueKey('${question.id}-row$i-$column'),
                          initialValue: rows[i][column]?.toString() ?? '',
                          enabled: enabled,
                          style: GoogleFonts.sora(fontSize: 12, color: AppColors.text),
                          decoration: InputDecoration(
                            labelText: column,
                            labelStyle: GoogleFonts.sora(fontSize: 11, color: AppColors.muted),
                            isDense: true,
                            border: InputBorder.none,
                          ),
                          onChanged: (v) {
                            final updated = List<Map<String, dynamic>>.from(rows);
                            updated[i] = {...updated[i], column: v};
                            updateAnswer(question.id, updated);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (enabled)
            OutlinedButton.icon(
              onPressed: () {
                final updated = List<Map<String, dynamic>>.from(rows)
                  ..add({for (final c in columns) c: ''});
                updateAnswer(question.id, updated);
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add row'),
            ),
        ],
      ],
    );
  }

  Widget _optionRow(String label, bool selected, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange : AppColors.orange.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.orange : AppColors.border,
              width: selected ? 1.8 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.orange.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.text,
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? Colors.white : AppColors.slate,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _multiSelectField(Question question, dynamic value, bool enabled) {
    final selected = value is List ? value.map((e) => '$e').toSet() : <String>{};

    return Column(
      children: [
        for (final option in question.options)
          _optionRow(
            option,
            selected.contains(option),
            enabled
                ? () {
                    final updated = Set<String>.from(selected);
                    if (selected.contains(option)) {
                      updated.remove(option);
                    } else {
                      updated.add(option);
                    }
                    updateAnswer(question.id, updated.toList());
                  }
                : null,
          ),
      ],
    );
  }

  Widget _singleSelectField(Question question, String? value, bool enabled) {
    final options = question.options;

    // A long option list collapses to a dropdown instead of a wall of rows.
    if (options.length > 5) {
      final current = value != null && options.contains(value) ? value : null;
      return Container(
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonHideUnderline(
          child: DropdownButtonFormField<String>(
            initialValue: current,
            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            hint: Text('Select an option...', style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted)),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.navy),
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: option,
                  child: Text(option, style: GoogleFonts.sora(fontSize: 13, color: AppColors.text)),
                ),
            ],
            onChanged: enabled ? (v) => updateAnswer(question.id, v) : null,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final option in options)
          _optionRow(
            option,
            value?.trim() == option.trim(),
            enabled ? () => updateAnswer(question.id, option) : null,
          ),
      ],
    );
  }

  Widget _datePickerField(
    Question question,
    dynamic value,
    bool enabled, {
    required bool withTime,
  }) {
    final text = value as String? ?? '';

    return GestureDetector(
      onTap: enabled
          ? () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(text) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date == null || !mounted) return;

              var result = date;
              if (withTime) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (time == null || !mounted) return;
                result = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              }

              final formatted = withTime
                  ? '${_pad4(result.year)}-${_pad2(result.month)}-${_pad2(result.day)} '
                      '${_pad2(result.hour)}:${_pad2(result.minute)}:00'
                  : '${_pad4(result.year)}-${_pad2(result.month)}-${_pad2(result.day)}';
              updateAnswer(question.id, formatted);
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              text.isEmpty ? 'Choose a date...' : text,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: text.isEmpty ? AppColors.muted : AppColors.text,
              ),
            ),
            Icon(
              withTime ? Icons.access_time_outlined : Icons.calendar_today_outlined,
              color: AppColors.navy,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratingField(Question question, dynamic value, bool enabled) {
    final rating = value is num ? value.round() : 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starPos = index + 1;
        final filled = rating >= starPos;
        return GestureDetector(
          onTap: enabled ? () => updateAnswer(question.id, starPos) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              color: filled ? const Color(0xFFFFB020) : AppColors.slate,
              size: 32,
            ),
          ),
        );
      }),
    );
  }

  Widget _switchField(dynamic value, bool enabled, String onLabel, String offLabel, void Function(bool) onChanged) {
    final checked = value == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: AppColors.light, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            value == null ? 'Not answered' : (checked ? onLabel : offLabel),
            style: GoogleFonts.sora(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: value == null ? AppColors.muted : (checked ? AppColors.green : AppColors.muted),
            ),
          ),
          Switch(
            value: checked,
            activeThumbColor: AppColors.orange,
            activeTrackColor: AppColors.orange.withValues(alpha: 0.3),
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _textLikeField(
    Question question,
    dynamic value,
    bool enabled, {
    bool multiline = false,
    bool numeric = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.light,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: multiline ? 10 : 2),
      child: TextFormField(
        initialValue: numeric ? (value?.toString() ?? '') : (value as String? ?? ''),
        enabled: enabled,
        maxLines: multiline ? 4 : 1,
        keyboardType:
            numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        style: GoogleFonts.sora(fontSize: 13, color: enabled ? AppColors.text : AppColors.muted),
        decoration: InputDecoration(
          hintText: question.help?.isNotEmpty == true
              ? question.help
              : (numeric ? 'Enter value...' : 'Type here...'),
          hintStyle: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
          border: InputBorder.none,
          isDense: true,
        ),
        onChanged: (v) => updateAnswer(question.id, numeric ? num.tryParse(v) : v),
      ),
    );
  }

  Widget _questionField(
    Question question,
    dynamic value,
    bool enabled,
    String link,
  ) {
    if (link.isNotEmpty) {
      return _linkField(question, value as String?, enabled, link);
    }

    switch (question.type) {
      case 'text':
        return _textLikeField(question, value, enabled);

      case 'textarea':
        return _textLikeField(question, value, enabled, multiline: true);

      case 'number':
      case 'currency':
        return _textLikeField(question, value, enabled, numeric: true);

      case 'rating':
        return _ratingField(question, value, enabled);

      case 'date':
        return _datePickerField(question, value, enabled, withTime: false);

      case 'datetime':
        return _datePickerField(question, value, enabled, withTime: true);

      case 'yes_no':
        return _switchField(
          value,
          enabled,
          'Yes',
          'No',
          (v) => updateAnswer(question.id, v),
        );

      case 'checkbox':
        if (question.options.isEmpty) {
          return _switchField(
            value,
            enabled,
            'Checked',
            'Unchecked',
            (v) => updateAnswer(question.id, v),
          );
        }
        return _multiSelectField(question, value, enabled);

      case 'multi_select':
        return _multiSelectField(question, value, enabled);

      case 'select':
      case 'radio':
        return _singleSelectField(question, value as String?, enabled);

      case 'table':
        return _tableField(question, value, enabled);

      case 'image':
        return _imageField(question, value as String?, enabled);

      case 'signature':
        return _signatureField(question, value as String?, enabled);

      case 'file':
        return _fileField(question, value as String?, enabled);

      default:
        return _textLikeField(question, value, enabled);
    }
  }

  Widget buildQuestion(Question question, int number) {
    final behaviour = FieldBehaviour.parse(question.rule);
    final enabled = !behaviour.readOnly;
    final badge = _fieldMeta(question, behaviour.link);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    number.toString().padLeft(2, '0'),
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.light,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(badge.$1, style: const TextStyle(fontSize: 10)),
                          const SizedBox(width: 4),
                          Text(
                            badge.$2,
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            question.label,
                            style: GoogleFonts.sora(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (question.required)
                          Padding(
                            padding: const EdgeInsets.only(left: 3, top: 1),
                            child: Text(
                              '*',
                              style: GoogleFonts.sora(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.red,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (question.help != null && question.help!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        question.help!,
                        style: GoogleFonts.sora(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!enabled) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.light,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 12, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text(
                    'READ ONLY',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          _questionField(question, answers[question.id], enabled, behaviour.link),
        ],
      ),
    );
  }

  Widget _buildProgressCard(int done, int total) {
    final progress = total == 0 ? 0.0 : done / total;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Required fields',
                style: GoogleFonts.sora(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              Text(
                '$done of $total done',
                style: GoogleFonts.sora(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.light,
              valueColor: const AlwaysStoppedAnimation(AppColors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitBar() {
    final busy = isSubmitting || backgroundSynced;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ScaleButton(
        onTap: busy ? null : _confirmAndSubmit,
        scaleBound: 0.97,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: busy ? AppColors.orange.withValues(alpha: 0.5) : AppColors.orange,
            borderRadius: BorderRadius.circular(14),
            boxShadow: busy
                ? []
                : [
                    BoxShadow(
                      color: AppColors.orange.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Submit Form',
                      style: GoogleFonts.sora(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = submission;
    final visible = current != null ? _visibleQuestions(current) : const <Question>[];
    final totalRequired = visible.where((q) => q.required).length;
    final answeredRequired =
        visible.where((q) => q.required && _isAnswered(answers[q.id])).length;

    return Scaffold(
      backgroundColor: AppColors.light,
      body: Column(
        children: [
          Container(
            color: AppColors.navy,
            child: Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + 8),
                AppNavBar(
                  title: current?.form.title ?? widget.formTitle ?? 'Draft',
                  breadcrumb: current != null ? 'FORM · ${current.form.id}' : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
                : errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: AppColors.red),
                              const SizedBox(height: 16),
                              Text(
                                errorMessage!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: createDraft,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : current == null
                        ? const SizedBox.shrink()
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              if (totalRequired > 0)
                                _buildProgressCard(answeredRequired, totalRequired),
                              for (var i = 0; i < visible.length; i++)
                                buildQuestion(visible[i], i + 1),
                              if (backgroundSynced)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    'Already submitted — further edits here would start a new draft.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.sora(fontSize: 12, color: AppColors.muted),
                                  ),
                                ),
                            ],
                          ),
          ),
        ],
      ),
      bottomNavigationBar:
          (isLoading || errorMessage != null || current == null) ? null : _buildSubmitBar(),
    );
  }
}
