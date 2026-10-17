import 'package:flutter/material.dart';

/// Shown above a list screen's body when it's displaying the last cached
/// response instead of a fresh one (offline, or the live fetch failed).
Widget cachedDataBanner() => Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: const Text(
        'Showing saved data from your last visit — pull to refresh.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12),
      ),
    );
