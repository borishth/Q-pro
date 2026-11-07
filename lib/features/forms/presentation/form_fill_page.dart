import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/permissions.dart';
import '../../../core/network/app_errors.dart';
import '../../../core/network/session.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/geo_stamp_service.dart';
import '../../../core/services/photo_stamper.dart';
import '../../../core/storage/outbox_db.dart';
import '../../../core/storage/outbox_sync.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_nav_bar.dart';
import '../../../core/widgets/mic_dictation_button.dart';
import '../../../core/widgets/scale_button.dart';
import '../../../core/widgets/state_views.dart';
import '../models/field_behaviour.dart';
import '../models/form_payload.dart';
import '../models/question.dart';
import '../models/submission_detail.dart';
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
  bool isSavingDraft = false;
  String? errorMessage;
  SubmissionDetail? submission;
  final Map<String, dynamic> answers = {};
  final Map<String, bool> uploading = {};

  /// Question ids whose photo is having its location stamp applied —
  /// waiting on a GPS fix, so worth showing rather than looking frozen.
  final Map<String, bool> stamping = {};
  final Map<String, String> pendingUploadPaths = {};
  final ImagePicker _imagePicker = ImagePicker();

  /// True once this page is working against a local draft row rather than
  /// calling the server directly. Always the case: opening a form creates
  /// nothing on the server, and edits only land in this device's draft row
  /// until the user taps Save Draft or Submit.
  bool isLocalDraft = false;

  /// True while this fill has never been saved or submitted, so it exists
  /// only on this device (a `scratch` draft row). The next time the same
  /// form is opened, [openForm] hands it back.
  bool isScratch = false;

  /// True once Save Draft or Submit has sent (or queued) this fill.
  bool savedToServer = false;

  /// Edits made since the last Save Draft — the server doesn't have them
  /// yet, and leaving would drop them, so the back button asks first.
  bool hasUnsavedEdits = false;

  /// True once a background sync finishes this exact draft (its `submit`
  /// job completed) while this screen was still open — further edits are
  /// blocked so the user can't queue a second submit on an already-done
  /// draft (see `_reconcileWithBackgroundSync`).
  bool backgroundSynced = false;

  /// True when this page opened a draft that has already been submitted —
  /// the Drafts screen's "View". The server has it and reopening can't send
  /// it again, so every field renders disabled and the submit bar is
  /// replaced by a note saying as much.
  bool isViewOnly = false;

  @override
  void initState() {
    super.initState();
    isOnline.addListener(_handleConnectivityChange);
    OutboxSync.instance.pendingCount.addListener(_handleQueueChange);
    // A cold GPS fix and NTP sync take seconds; start them now so a photo
    // taken later in the form doesn't wait on them.
    PhotoStampService.instance.prewarm();
    final resumeId = widget.resumeLocalId;
    if (resumeId != null) {
      _resumeDraft(resumeId);
    } else {
      openForm();
    }
  }

  @override
  void dispose() {
    isOnline.removeListener(_handleConnectivityChange);
    OutboxSync.instance.pendingCount.removeListener(_handleQueueChange);
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
    if (current == null || !isLocalDraft || isViewOnly || !mounted) return;

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

  /// Opens the form for filling without creating anything on the server:
  /// the questions come from a read-only `get_form` (or the cache when
  /// offline), and the answers live in a local `scratch` draft until the
  /// user taps Save Draft or Submit. A fill left unfinished last time is
  /// restored instead of starting over.
  Future<void> openForm() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final formId = widget.formId!;

    if (isOnline.value) {
      try {
        await _cacheFormPayload(await infrive.getForm(formId));
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
        // Lost connection mid-request: fall back to the cached questions.
      }
    }

    final unfinished = await OutboxDatabase.instance.getScratchDraft(
      formId,
      widget.stageId,
    );
    if (!mounted) return;

    if (unfinished != null) {
      await _resumeDraft(unfinished['local_id'] as String);
    } else {
      await _createScratchDraft();
    }
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

  Future<void> _createScratchDraft() async {
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
      state: OutboxDatabase.scratchState,
    );

    if (!mounted) return;
    setState(() {
      isLocalDraft = true;
      isScratch = true;
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

    // Already submitted: this is a look back at what was sent, not an edit.
    final submitted = draft['state'] == OutboxDatabase.syncedState;

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
      isViewOnly = submitted;
      isScratch = draft['state'] == OutboxDatabase.scratchState;
      submission = SubmissionDetail(
        name: localId,
        status: submitted ? 'Submitted' : 'Draft',
        project: '',
        stage: (draft['stage'] as String?) ?? '',
        form: FormPayload.fromJson(cached as Map<String, dynamic>),
        answers: savedAnswers,
        editable: !submitted,
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
    // A submitted draft is the record of what was sent; nothing changes it.
    if (isViewOnly) return;
    setState(() {
      answers[questionId] = value;
      if (savedToServer) hasUnsavedEdits = true;
    });

    final current = submission;
    if (current == null) return;

    // Edits only ever land in this device's draft row; the server hears
    // about them when the user taps Save Draft or Submit.
    OutboxDatabase.instance.updateDraftAnswers(current.name, answers);
  }

  Future<void> pickImage(Question question, ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;
    await uploadFileAnswer(question, await _geoStamped(question, File(picked.path)));
  }

  /// Burns the current position and time onto a photo before it is queued.
  ///
  /// Gallery picks are stamped as well as camera shots: the band records
  /// where and when the stamp was applied, which for a gallery photo is
  /// not where the shot was taken. A failure here never costs the photo —
  /// the original is attached unstamped.
  Future<File> _geoStamped(Question question, File photo) async {
    setState(() => stamping[question.id] = true);
    try {
      final stamp = await PhotoStampService.instance.capture();
      if (mounted && stamp.failure != null) {
        _reportStampFailure(stamp.failure!);
      }
      return await stampPhoto(photo, stamp);
    } catch (_) {
      return photo;
    } finally {
      if (mounted) setState(() => stamping.remove(question.id));
    }
  }

  /// Tells the user the photo went up without a location, and offers the
  /// one action that can actually fix it. A denied permission can only be
  /// undone in system settings; a missed fix is just worth retrying.
  void _reportStampFailure(GeoStampFailure failure) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('${failure.label} — stamping the time only.'),
          action: failure.openSettingsHelps
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: () => failure == GeoStampFailure.servicesOff
                      ? Geolocator.openLocationSettings()
                      : Geolocator.openAppSettings(),
                )
              : SnackBarAction(
                  label: 'Retry',
                  onPressed: PhotoStampService.instance.prewarm,
                ),
        ),
      );
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
    // and a draft the server already knows about, so it's queued and waits
    // for the draft's first Save Draft or Submit.
    setState(() => pendingUploadPaths[question.id] = file.path);
    await OutboxDatabase.instance.enqueueUpload(
      current.name,
      question.id,
      file.path,
    );
    OutboxSync.instance.wake();
  }

  Future<void> submit() async {
    final current = submission;
    if (current == null) return;

    setState(() => isSubmitting = true);
    await OutboxDatabase.instance.updateDraftAnswers(current.name, answers);

    // Straight to the server when there's a connection and no photo still
    // waiting to upload, so a problem (a missing required answer, say)
    // shows up right here. Otherwise it goes through the queue, which
    // keeps the save -> upload -> submit order.
    if (isOnline.value && pendingUploadPaths.isEmpty) {
      try {
        final serverName = await _saveToServer(current.name);
        await infrive.submit(serverName, answers: answers);
        await OutboxDatabase.instance.setDraftState(current.name, 'synced');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submitted.')),
        );
        Navigator.of(context).pop();
        return;
      } catch (error) {
        if (!mounted) return;
        if (isSessionExpired(error)) {
          signOutToLogin(context);
          return;
        }
        if (error is! NetworkException) {
          setState(() => isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(describeError(error))),
          );
          return;
        }
        // Lost connection mid-request: queue it instead.
      }
    }

    await OutboxDatabase.instance.enqueueSaveAheadOfUploads(current.name);
    await OutboxDatabase.instance.enqueueIfAbsent('submit', current.name);
    await _leaveScratch(current.name);
    OutboxSync.instance.wake();

    if (!mounted) return;
    setState(() => isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Saved — it'll submit as soon as it can sync."),
      ),
    );
    Navigator.of(context).pop();
  }

  /// Writes the draft's answers to the server — creating the submission the
  /// first time — and returns its name. The name is stored on the draft
  /// right away, so a retry updates that submission instead of creating
  /// another one.
  Future<String> _saveToServer(String localId) async {
    final draft = (await OutboxDatabase.instance.getDraft(localId))!;
    final existing = draft['server_name'] as String?;
    final saved = await infrive.saveSubmission(
      form: draft['form'] as String,
      stage: draft['stage'] as String?,
      submission: existing,
      answers: answers,
    );
    if (existing == null) {
      await OutboxDatabase.instance.setDraftServerName(localId, saved.name);
    }
    if (mounted) setState(() => isScratch = false);
    return saved.name;
  }

  /// Takes a never-saved draft off the scratch shelf once it's headed to
  /// the server through the queue, so it shows up as a pending draft.
  Future<void> _leaveScratch(String localId) async {
    final draft = await OutboxDatabase.instance.getDraft(localId);
    if (draft?['state'] == OutboxDatabase.scratchState) {
      await OutboxDatabase.instance.setDraftState(localId, 'local');
    }
    if (mounted) setState(() => isScratch = false);
  }

  Future<void> saveDraft() async {
    final current = submission;
    if (current == null) return;

    setState(() => isSavingDraft = true);
    await OutboxDatabase.instance.updateDraftAnswers(current.name, answers);

    // Same split as submit: direct when it can be, queued otherwise.
    if (isOnline.value && pendingUploadPaths.isEmpty) {
      try {
        await _saveToServer(current.name);

        if (!mounted) return;
        setState(() {
          isSavingDraft = false;
          savedToServer = true;
          hasUnsavedEdits = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft saved.')),
        );
        return;
      } catch (error) {
        if (!mounted) return;
        if (isSessionExpired(error)) {
          signOutToLogin(context);
          return;
        }
        if (error is! NetworkException) {
          setState(() => isSavingDraft = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(describeError(error))),
          );
          return;
        }
        // Lost connection mid-request: queue it instead.
      }
    }

    await OutboxDatabase.instance.enqueueSaveAheadOfUploads(current.name);
    await _leaveScratch(current.name);
    OutboxSync.instance.wake();

    if (!mounted) return;
    setState(() {
      isSavingDraft = false;
      savedToServer = true;
      hasUnsavedEdits = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isOnline.value
              ? 'Draft saved — attachments are still uploading.'
              : "Saved offline — it'll sync once you're back online.",
        ),
      ),
    );
  }

  /// Clears an unsaved fill: nothing was ever sent to the server, so this
  /// just drops the local copy (and any photos queued with it) and leaves.
  Future<void> _confirmAndClear() async {
    final current = submission;
    if (current == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this form?'),
        content: const Text(
          "Everything you've entered will be removed. Nothing has been saved yet.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await OutboxDatabase.instance.deleteDraftAndJobs(current.name);
    unawaited(OutboxSync.instance.refreshPendingCount());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Back was pressed with edits the server doesn't have yet (only possible
  /// after a Save Draft — before that the whole fill is kept on the device).
  Future<void> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You changed this form after your last Save Draft. Save those changes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save draft'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (choice == 'save') {
      await saveDraft();
      if (mounted && !hasUnsavedEdits) Navigator.of(context).pop();
    } else if (choice == 'discard') {
      setState(() => hasUnsavedEdits = false);
      Navigator.of(context).pop();
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
  /// A photo stays queued until the outbox drains it, which happens within
  /// seconds when there's a connection — so the note has to follow
  /// connectivity rather than assuming a queued file means offline.
  Widget _queuedUploadNote(Question question) {
    if (pendingUploadPaths[question.id] == null) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: isOnline,
      builder: (context, online, _) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Icon(
              online ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined,
              size: 13,
              color: AppColors.orange,
            ),
            const SizedBox(width: AppSpacing.xs + 2),
            Expanded(
              child: Text(
                online
                    ? 'Queued for upload.'
                    : "Will upload when you're back online.",
                style: GoogleFonts.sora(
                  fontSize: 11,
                  color: AppColors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageField(Question question, String? url, bool enabled) {
    final isUploading = uploading[question.id] ?? false;
    final isStamping = stamping[question.id] ?? false;
    final hasFile = pendingUploadPaths[question.id] != null ||
        (url != null && url.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filePreview(question, url, Icons.image_outlined),
        _queuedUploadNote(question),
        const SizedBox(height: 10),
        if (isStamping)
          Row(
            children: [
              const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Adding location…',
                style: GoogleFonts.sora(fontSize: 12, color: AppColors.muted),
              ),
            ],
          )
        else if (isUploading)
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
      child: _DictatableTextField(
        key: ValueKey('text-${question.id}'),
        initialText: numeric ? (value?.toString() ?? '') : (value as String? ?? ''),
        enabled: enabled,
        multiline: multiline,
        numeric: numeric,
        hint: question.help?.isNotEmpty == true
            ? question.help!
            : (numeric ? 'Enter value...' : 'Type here...'),
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
    final enabled = !behaviour.readOnly && !isViewOnly;

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

  /// Heads a submitted draft in place of the required-fields progress —
  /// there is no progress left to make on it.
  Widget _buildViewOnlyBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.tagGreenBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Submitted — these answers are read only.',
              style: GoogleFonts.sora(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Stands in for [_buildSubmitBar] on a submitted draft: nothing left to
  /// save and nothing left to send, so the only action is back out.
  Widget _buildViewOnlyBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ScaleButton(
        onTap: () => Navigator.of(context).maybePop(),
        scaleBound: 0.97,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.light,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            'Done',
            style: GoogleFonts.sora(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
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
    final busy = isSubmitting || isSavingDraft || backgroundSynced;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ScaleButton(
              onTap: busy ? null : saveDraft,
              scaleBound: 0.97,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border, width: 1.5),
                ),
                alignment: Alignment.center,
                child: isSavingDraft
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppColors.navy),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Save Draft',
                            style: GoogleFonts.sora(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.save_outlined, size: 16, color: AppColors.navy),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
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
                            'Submit',
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
          ),
        ],
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

    return PopScope(
      canPop: !hasUnsavedEdits,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
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
                  onBack: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
                : errorMessage != null
                    ? ErrorStateView(
                        message: errorMessage!,
                        onRetry: widget.resumeLocalId != null
                            ? () => _resumeDraft(widget.resumeLocalId!)
                            : openForm,
                      )
                    : current == null
                        ? const SizedBox.shrink()
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              if (isViewOnly)
                                _buildViewOnlyBanner()
                              else if (totalRequired > 0)
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
                              if (isScratch)
                                Center(
                                  child: TextButton.icon(
                                    onPressed: (isSubmitting || isSavingDraft) ? null : _confirmAndClear,
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    label: const Text('Clear form'),
                                    style: TextButton.styleFrom(foregroundColor: AppColors.red),
                                  ),
                                ),
                            ],
                          ),
          ),
        ],
      ),
      bottomNavigationBar: (isLoading || errorMessage != null || current == null)
          ? null
          : isViewOnly
              ? _buildViewOnlyBar()
              : _buildSubmitBar(),
      ),
    );
  }
}

/// Text answer field that owns its controller so dictated text can be
/// appended; shows a mic button for editable string (text/textarea) fields only.
/// Numeric fields have none — the small on-device model is too unreliable
/// for digits.
class _DictatableTextField extends StatefulWidget {
  const _DictatableTextField({
    super.key,
    required this.initialText,
    required this.enabled,
    required this.multiline,
    required this.numeric,
    required this.hint,
    required this.onChanged,
  });

  final String initialText;
  final bool enabled;
  final bool multiline;
  final bool numeric;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_DictatableTextField> createState() => _DictatableTextFieldState();
}

class _DictatableTextFieldState extends State<_DictatableTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _appendDictation(String text) {
    final existing = _controller.text.trim();
    final merged = existing.isEmpty ? text : '$existing $text';
    _controller.text = merged;
    widget.onChanged(merged);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          widget.multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: widget.enabled,
            maxLines: widget.multiline ? 4 : 1,
            keyboardType: widget.numeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            style: GoogleFonts.sora(
              fontSize: 13,
              color: widget.enabled ? AppColors.text : AppColors.muted,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: GoogleFonts.sora(fontSize: 13, color: AppColors.muted),
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: widget.onChanged,
          ),
        ),
        if (!widget.numeric && widget.enabled) ...[
          const SizedBox(width: 4),
          MicDictationButton(onTranscribed: _appendDictation),
        ],
      ],
    );
  }
}
