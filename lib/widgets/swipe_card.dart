import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Presentación únicamente. La decisión se delega al servicio existente.
class SwipeCard extends StatefulWidget {
  const SwipeCard({
    super.key,
    required this.child,
    required this.onDecision,
    this.onBusy,
    this.enabled = true,
    this.thresholdFraction = .28,
    this.maxThreshold = 120,
    this.rotation = .16,
  });
  final Widget child;
  final Future<bool> Function(bool like) onDecision;
  final ValueChanged<bool>? onBusy;
  final bool enabled;
  final double thresholdFraction, maxThreshold, rotation;
  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: AppMotion.normal,
  );
  Offset _drag = Offset.zero, _from = Offset.zero, _to = Offset.zero;
  double _width = 360;
  bool _busy = false;
  Offset get _offset => _motion.isAnimating
      ? Offset.lerp(_from, _to, AppMotion.curve.transform(_motion.value))!
      : _drag;
  Future<void> _animate(Offset to) async {
    _from = _drag;
    _to = to;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _drag = to);
      return;
    }
    try {
      await _motion.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted) {
      _drag = to;
      _motion.reset();
    }
  }

  Future<void> decide(bool like) async {
    if (_busy || !widget.enabled || _motion.isAnimating) return;
    setState(() => _busy = true);
    widget.onBusy?.call(true);
    try {
      HapticFeedback.selectionClick();
      await _animate(Offset((like ? 1 : -1) * (_width + 100), 30));
      if (!mounted) return;
      final accepted = await widget.onDecision(like);
      if (mounted && !accepted) await _animate(Offset.zero);
      if (!mounted) return;
      // Si el servicio conserva el perfil por un error de red, se restaura.
      _drag = Offset.zero;
    } on TickerCanceled {
      return;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusy?.call(false);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _width = box.maxWidth;
      return GestureDetector(
        key: const ValueKey('swipe-card-gesture'),
        onHorizontalDragStart: widget.enabled && !_busy && !_motion.isAnimating
            ? (_) {
                _motion.stop();
              }
            : null,
        onHorizontalDragUpdate: widget.enabled && !_busy
            ? (details) {
                if (_motion.isAnimating) return;
                setState(() => _drag += Offset(details.delta.dx, 0));
              }
            : null,
        onHorizontalDragCancel: () {
          if (!_busy) _animate(Offset.zero);
        },
        onHorizontalDragEnd: widget.enabled && !_busy
            ? (details) {
                final speed = details.primaryVelocity ?? 0;
                final flick =
                    _drag.dx.abs() >= 24 &&
                    speed.abs() >= 850 &&
                    speed.sign == _drag.dx.sign;
                if (flick ||
                    _drag.dx.abs() >=
                        math.min(
                          widget.maxThreshold,
                          _width * widget.thresholdFraction,
                        )) {
                  decide(_drag.dx > 0);
                } else {
                  _animate(Offset.zero);
                }
              }
            : null,
        child: AnimatedBuilder(
          animation: _motion,
          child: widget.child,
          builder: (context, child) {
            final offset = _offset;
            final reduce = MediaQuery.disableAnimationsOf(context);
            final reveal = (offset.dx.abs() / 150).clamp(0.0, 1.0);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: Transform.translate(
                      offset: Offset(0, reduce ? 5 : 7 - 4 * reveal),
                      child: Transform.scale(
                        scale: reduce ? .97 : .96 + .02 * reveal,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: offset,
                  child: Transform.rotate(
                    angle: reduce
                        ? 0
                        : (offset.dx / _width).clamp(-1, 1) * widget.rotation,
                    child: Stack(
                      children: [
                        child!,
                        if (offset.dx.abs() > 12)
                          Positioned(
                            top: 28,
                            left: offset.dx > 0 ? 24 : null,
                            right: offset.dx < 0 ? 24 : null,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: (offset.dx.abs() / 100).clamp(0, 1),
                                child: Transform.rotate(
                                  angle: reduce
                                      ? 0
                                      : offset.dx > 0
                                      ? -.15
                                      : .15,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: offset.dx > 0
                                            ? AppColors.green
                                            : AppColors.coral,
                                        width: 3,
                                      ),
                                    ),
                                    child: Text(
                                      offset.dx > 0 ? 'LIKE' : 'PASAR',
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                        color: offset.dx > 0
                                            ? AppColors.green
                                            : AppColors.coral,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
