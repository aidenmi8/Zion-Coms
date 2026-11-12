import 'package:flutter/material.dart';

/// Approved Zion artwork in the existing refresh and huddle animation slot.
/// The upstream API and dimensions remain stable for its callers.
class FlappingBee extends StatelessWidget {
  /// Width of the existing animation slot.
  final double width;

  /// Status color retained by the upstream presentation API.
  final Color color;

  /// Animation progress supplied by refresh and huddle consumers.
  final double flapAmount;

  /// Refresh interaction progress retained for upstream gesture behavior.
  final double? eyeProgress;

  const FlappingBee({
    required this.width,
    required this.color,
    required this.flapAmount,
    this.eyeProgress,
    super.key,
  });

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: width,
      height: width * 309 / 466,
      child: Transform.scale(
        scale: MediaQuery.disableAnimationsOf(context)
            ? 1
            : 1.0 - 0.04 * flapAmount.clamp(0.0, 1.0),
        child: Image.asset(
          'assets/images/zion-icon.png',
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}
