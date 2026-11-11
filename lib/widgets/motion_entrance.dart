import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A brief entrance that leaves layout, semantics and hit targets in place.
class MotionEntrance extends StatelessWidget {
  const MotionEntrance({
    super.key,
    required this.child,
    this.distance = 8,
    this.enabled = true,
  });
  final Widget child;
  final double distance;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final animate = enabled && !MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: animate ? 0 : 1, end: 1),
      duration: animate ? AppMotion.fast : Duration.zero,
      curve: AppMotion.curve,
      child: child,
      builder: (_, value, child) => Opacity(
        opacity: .65 + .35 * value,
        child: Transform.translate(
          offset: Offset(0, distance * (1 - value)),
          transformHitTests: false,
          child: child,
        ),
      ),
    );
  }
}

/// The chat transition uses compositing only and keeps platform back navigation.
Route<void> conversationRoute(BuildContext context, WidgetBuilder builder) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<void>(
    pageBuilder: (context, _, _) => builder(context),
    transitionDuration: reduced ? Duration.zero : AppMotion.normal,
    reverseTransitionDuration: reduced ? Duration.zero : AppMotion.fast,
    transitionsBuilder: (_, animation, _, child) {
      final progress = animation.drive(CurveTween(curve: AppMotion.curve));
      return FadeTransition(
        opacity: progress,
        child: SlideTransition(
          position: progress.drive(
            Tween(begin: const Offset(.035, 0), end: Offset.zero),
          ),
          child: child,
        ),
      );
    },
  );
}
