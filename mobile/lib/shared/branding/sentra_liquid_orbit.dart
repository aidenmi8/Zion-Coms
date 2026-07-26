import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:buzz/shared/branding/sentra_branding.dart';
import 'package:buzz/shared/theme/theme.dart';

/// The duration of the one-shot Sentra liquid-orb animation.
const sentraLiquidOrbitDuration = Duration(milliseconds: 7600);

/// A one-shot, dissolving liquid-orb treatment behind the Sentra wordmark.
class SentraLiquidOrbit extends HookWidget {
  const SentraLiquidOrbit({super.key, this.wordmarkHeight = 88});

  /// The rendered height of the Sentra wordmark.
  final double wordmarkHeight;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final controller = useAnimationController(
      duration: sentraLiquidOrbitDuration,
    );

    useEffect(() {
      if (reducedMotion) {
        controller.value = 1;
      } else {
        unawaited(controller.forward(from: 0));
      }
      return null;
    }, [controller, reducedMotion]);

    return Semantics(
      label: 'Sentra',
      image: true,
      child: SizedBox(
        height: wordmarkHeight * 1.7,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _DissolvedLiquidOrb(controller: controller),
            Image.asset(
              sentraWordmarkAssetFor(context.colors.brightness),
              height: wordmarkHeight,
            ),
          ],
        ),
      ),
    );
  }
}

class _DissolvedLiquidOrb extends StatelessWidget {
  const _DissolvedLiquidOrb({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) {
      final progress = Curves.easeOutCubic.transform(controller.value);
      final color = context.colors.primary;

      return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const RadialGradient(
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0, 0.26, 0.72, 1],
        ).createShader(bounds),
        child: ClipOval(
          child: SizedBox.square(
            dimension: 196,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _LiquidLayer(
                  color: color,
                  opacity: 0.01,
                  beginOffset: const Offset(-19, 14),
                  endOffset: Offset.zero,
                  beginScale: 1.16,
                  endScale: 1,
                  progress: progress,
                ),
                _LiquidLayer(
                  color: color,
                  opacity: 0.006,
                  beginOffset: const Offset(24, -17),
                  endOffset: const Offset(6, -3),
                  beginScale: 0.74,
                  endScale: 0.88,
                  progress: progress,
                ),
                _LiquidLayer(
                  color: color,
                  opacity: 0.004,
                  beginOffset: const Offset(-28, -5),
                  endOffset: const Offset(-9, 6),
                  beginScale: 0.62,
                  endScale: 0.76,
                  progress: progress,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _LiquidLayer extends StatelessWidget {
  const _LiquidLayer({
    required this.color,
    required this.opacity,
    required this.beginOffset,
    required this.endOffset,
    required this.beginScale,
    required this.endScale,
    required this.progress,
  });

  final Color color;
  final double opacity;
  final Offset beginOffset;
  final Offset endOffset;
  final double beginScale;
  final double endScale;
  final double progress;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset.lerp(beginOffset, endOffset, progress)!,
    child: Transform.scale(
      scale: beginScale + (endScale - beginScale) * progress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: opacity * 0.35),
              Colors.transparent,
            ],
            stops: const [0, 0.52, 1],
          ),
        ),
      ),
    ),
  );
}
