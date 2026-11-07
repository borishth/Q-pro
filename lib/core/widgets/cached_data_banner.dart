import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Shown above a list screen's body when it's displaying the last cached
/// response instead of a fresh one (offline, or the live fetch failed).
///
/// Deliberately quiet: saved data is still useful data, and the global
/// offline banner in `main.dart` already carries the louder warning. This
/// one only answers "why might this look out of date?", so it sits on the
/// neutral surface rather than the amber it used to use — which matched
/// nothing else in the app and read as a warning about the data itself.
Widget cachedDataBanner() => Container(
      width: double.infinity,
      color: AppColors.light,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm + 2,
        horizontal: AppSpacing.lg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.history_rounded,
            size: 15,
            color: AppColors.slate,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'Saved from your last visit — pull to refresh.',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
