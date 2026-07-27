import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'zion_brand_tokens.dart';

class ZionBrandMotion extends HookConsumerWidget {
  final String variant;
  final bool playing;
  final bool? loop;
  final String? label;
  final double size;

  const ZionBrandMotion({
    super.key,
    this.variant = ZionBrandMotionVariants.loader,
    this.playing = true,
    this.loop,
    this.label,
    this.size = ZionBrandTokens.defaultMotionSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final spec = zionBrandMotionSpecFor(variant);
    final shouldLoop = loop ?? spec.loop;
    final controller = useAnimationController(
      duration: reducedMotion ? Duration.zero : spec.totalDuration,
      initialValue: reducedMotion || !playing ? 1 : 0,
    );

    useEffect(() {
      controller.duration = reducedMotion ? Duration.zero : spec.totalDuration;
      if (reducedMotion || !playing) {
        controller.stop();
        controller.value = 1;
        return null;
      }

      controller.stop();
      if (shouldLoop) {
        controller.repeat();
      } else {
        unawaited(controller.forward(from: 0));
      }

      return controller.stop;
    }, [controller, reducedMotion, playing, shouldLoop, spec.totalDuration]);

    final staticPose =
        reducedMotion
            ? spec.reducedMotionPose
            : playing
            ? null
            : spec.pausedPose;

    final opacityAnimation = _resolveAnimation(
      controller: controller,
      keyframes: spec.keyframes,
      selector: (pose) => pose.opacity,
      staticValue: staticPose?.opacity,
    );
    final scaleAnimation = _resolveAnimation(
      controller: controller,
      keyframes: spec.keyframes,
      selector: (pose) => pose.scale,
      staticValue: staticPose?.scale,
    );
    final translateAnimation = _resolveAnimation(
      controller: controller,
      keyframes: spec.keyframes,
      selector: (pose) => pose.translateY,
      staticValue: staticPose?.translateY,
    );
    final glowBlurAnimation = _resolveAnimation(
      controller: controller,
      keyframes: spec.keyframes,
      selector: (pose) => pose.glowBlur,
      staticValue: staticPose?.glowBlur,
    );
    final glowOpacityAnimation = _resolveAnimation(
      controller: controller,
      keyframes: spec.keyframes,
      selector: (pose) => pose.glowOpacity,
      staticValue: staticPose?.glowOpacity,
    );

    final image = ExcludeSemantics(
      child: Image.asset(
        ZionBrandAssets.iconPng,
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );

    final motion = AnimatedBuilder(
      animation: Listenable.merge([
        opacityAnimation,
        scaleAnimation,
        translateAnimation,
        glowBlurAnimation,
        glowOpacityAnimation,
      ]),
      child: ScaleTransition(
        scale: scaleAnimation,
        child: FadeTransition(opacity: opacityAnimation, child: image),
      ),
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, translateAnimation.value),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: ZionBrandTokens.markGlowColor.withValues(
                    alpha: glowOpacityAnimation.value,
                  ),
                  blurRadius: glowBlurAnimation.value * size,
                  spreadRadius: glowOpacityAnimation.value * size * 0.02,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );

    final content = SizedBox.square(
      key: ValueKey('zion-brand-motion-$variant'),
      dimension: size,
      child: Center(child: motion),
    );

    if (label == null || label!.isEmpty) {
      return ExcludeSemantics(child: content);
    }

    return Semantics(container: true, image: true, label: label, child: content);
  }
}

Animation<double> _resolveAnimation({
  required AnimationController controller,
  required List<ZionBrandMotionKeyframe> keyframes,
  required double Function(ZionBrandMotionPose pose) selector,
  double? staticValue,
}) {
  if (staticValue != null) {
    return AlwaysStoppedAnimation(staticValue);
  }

  if (keyframes.length <= 1) {
    return AlwaysStoppedAnimation(selector(keyframes.single.pose));
  }

  final items = <TweenSequenceItem<double>>[];
  for (var index = 0; index < keyframes.length - 1; index++) {
    final current = keyframes[index];
    final next = keyframes[index + 1];
    final weight = (next.progress - current.progress) * 1000;
    items.add(
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: selector(current.pose),
          end: selector(next.pose),
        ),
        weight: weight <= 0 ? 1 : weight,
      ),
    );
  }

  return controller.drive(TweenSequence<double>(items));
}
