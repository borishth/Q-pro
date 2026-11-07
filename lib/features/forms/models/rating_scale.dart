/// The compliance rating an approver gives alongside an approval.
///
/// Mirrors `RATING_LABELS` in the backend's `workflow/workflow_service.py`
/// — change both together. Only the *number* crosses the wire: the server
/// derives its own label and snapshots it onto the action log, so these
/// strings drive the picker's live preview and nothing else. Past ratings
/// are displayed from the stored remark, not from this table.
const ratingScale = <int, String>{
  1: 'Critical Non-Compliance',
  2: 'Minor Deficiencies Found',
  3: 'Standard Compliance Verified',
  4: 'High Quality Standards Verified',
  5: 'Outstanding Quality & Zero Defects',
};

const minRating = 1;
const maxRating = 5;

/// Label for [rating], or null when it is absent or outside the scale.
String? ratingLabel(int? rating) => rating == null ? null : ratingScale[rating];
