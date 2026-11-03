import 'package:flutter/material.dart';

/// ConstructionHub's page transition: a gentle 5% slide up from the bottom
/// combined with a fade-in. Registered through [PageTransitionsTheme] so every
/// existing `MaterialPageRoute` picks it up without touching call sites.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = Tween<Offset>(
      begin: const Offset(0.0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  }
}

const PageTransitionsTheme smoothPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: SmoothPageTransitionsBuilder(),
    TargetPlatform.iOS: SmoothPageTransitionsBuilder(),
    TargetPlatform.linux: SmoothPageTransitionsBuilder(),
    TargetPlatform.macOS: SmoothPageTransitionsBuilder(),
    TargetPlatform.windows: SmoothPageTransitionsBuilder(),
  },
);
