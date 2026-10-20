import 'package:flutter/material.dart';

/// Functional motion only: no timers or animation work while the UI is idle.
abstract final class AppMotion {
  static const state = Duration(milliseconds: 160);
  static const panel = Duration(milliseconds: 240);
  static const curve = Curves.easeInOutCubicEmphasized;
  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
  static AnimationStyle sheet(BuildContext context) => AnimationStyle(
    duration: duration(context, panel),
    reverseDuration: duration(context, const Duration(milliseconds: 200)),
  );
}

/// Animate just the changing region; keep the surrounding scroll viewport fixed.
class AppReveal extends StatelessWidget {
  const AppReveal({super.key, required this.visible, required this.child});
  final bool visible;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: AppMotion.duration(context, AppMotion.panel),
    curve: AppMotion.curve,
    alignment: Alignment.topCenter,
    child: visible ? child : const SizedBox(width: double.infinity),
  );
}
