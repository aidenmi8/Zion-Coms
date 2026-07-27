import 'package:flutter/material.dart';

abstract final class ZionBrandAssets {
  static const iconPng = 'assets/images/zion-icon.png';
  static const zionMarkSvg = 'assets/images/zion-mark.svg';
  static const sentraLockupLightSvg = 'assets/images/sentra-lockup-light.svg';
  static const sentraLockupDarkSvg = 'assets/images/sentra-lockup-dark.svg';

  static const zionIconSha256 =
      '4ea736a6dad74fddcb3ef19690ffaf6e62a5dfb738207d628121cfdc7c6cab50';
  static const zionMarkSha256 =
      'fd0d912d30cb3b817df0b3167b7c77f6929cfa0d0b8f1407c9b1d6d9e7acd124';
  static const sentraLockupLightSha256 =
      'fe7a257f666946b064571bcd73700f30ebf33e0bcd5076f47790bda076c9b01d';
  static const sentraLockupDarkSha256 =
      '087a92c1efdaba769e851fc72638f777e8f89adb8530f6661428536ee4b0c9d5';
}

abstract final class ZionBrandMotionVariants {
  static const loader = 'loader';
  static const onboarding = 'onboarding';
  static const liveness = 'liveness';
  static const pairing = 'pairing';
  static const agentEntrance = 'agent-entrance';

  static const values = <String>[
    loader,
    onboarding,
    liveness,
    pairing,
    agentEntrance,
  ];
}

enum ZionBrandReducedMotionPolicy { staticMark, settled }

@immutable
class ZionBrandMotionPose {
  final double opacity;
  final double scale;
  final double translateY;
  final double glowBlur;
  final double glowOpacity;

  const ZionBrandMotionPose({
    required this.opacity,
    required this.scale,
    required this.translateY,
    required this.glowBlur,
    required this.glowOpacity,
  });
}

@immutable
class ZionBrandMotionKeyframe {
  final double progress;
  final ZionBrandMotionPose pose;

  const ZionBrandMotionKeyframe({required this.progress, required this.pose});
}

@immutable
class ZionBrandMotionSpec {
  final String variant;
  final Duration duration;
  final Duration settleDuration;
  final Duration staggerDuration;
  final bool loop;
  final ZionBrandReducedMotionPolicy reducedMotionPolicy;
  final ZionBrandMotionPose pausedPose;
  final ZionBrandMotionPose reducedMotionPose;
  final List<ZionBrandMotionKeyframe> keyframes;

  const ZionBrandMotionSpec({
    required this.variant,
    required this.duration,
    this.settleDuration = Duration.zero,
    this.staggerDuration = Duration.zero,
    required this.loop,
    required this.reducedMotionPolicy,
    required this.pausedPose,
    required this.reducedMotionPose,
    required this.keyframes,
  });

  Duration get totalDuration => duration + settleDuration;
}

abstract final class ZionBrandTokens {
  static const markGlowColor = Color(0xFFB99AFF);
  static const defaultMotionSize = 64.0;
  static const heroMotionSize = 72.0;
  static const lockupWidthFactor = 2.9;
}

enum ZionBrandMotionAssetKind { mark, lockup }

@immutable
class ZionBrandMotionAsset {
  final String path;
  final ZionBrandMotionAssetKind kind;

  const ZionBrandMotionAsset({required this.path, required this.kind});

  bool get isLockup => kind == ZionBrandMotionAssetKind.lockup;

  double widthForHeight(double height) {
    return isLockup ? height * ZionBrandTokens.lockupWidthFactor : height;
  }
}

const _loaderPausedPose = ZionBrandMotionPose(
  opacity: 0.92,
  scale: 1,
  translateY: 0,
  glowBlur: 0.35,
  glowOpacity: 0.08,
);

const _loaderReducedMotionPose = ZionBrandMotionPose(
  opacity: 0.9,
  scale: 1,
  translateY: 0,
  glowBlur: 0.25,
  glowOpacity: 0.1,
);

const _settledPose = ZionBrandMotionPose(
  opacity: 1,
  scale: 1,
  translateY: 0,
  glowBlur: 0.35,
  glowOpacity: 0.1,
);

const _livenessPausedPose = ZionBrandMotionPose(
  opacity: 0.88,
  scale: 1,
  translateY: 0,
  glowBlur: 0.15,
  glowOpacity: 0.05,
);

const _livenessReducedMotionPose = ZionBrandMotionPose(
  opacity: 0.9,
  scale: 1,
  translateY: 0,
  glowBlur: 0.25,
  glowOpacity: 0.1,
);

const Map<String, ZionBrandMotionSpec> _zionBrandMotionSpecs = {
  ZionBrandMotionVariants.loader: ZionBrandMotionSpec(
    variant: ZionBrandMotionVariants.loader,
    duration: Duration(milliseconds: 1800),
    loop: true,
    reducedMotionPolicy: ZionBrandReducedMotionPolicy.staticMark,
    pausedPose: _loaderPausedPose,
    reducedMotionPose: _loaderReducedMotionPose,
    keyframes: [
      ZionBrandMotionKeyframe(
        progress: 0,
        pose: ZionBrandMotionPose(
          opacity: 0.76,
          scale: 0.965,
          translateY: 0,
          glowBlur: 0.35,
          glowOpacity: 0.08,
        ),
      ),
      ZionBrandMotionKeyframe(
        progress: 0.5,
        pose: ZionBrandMotionPose(
          opacity: 1,
          scale: 1,
          translateY: 0,
          glowBlur: 0.8,
          glowOpacity: 0.22,
        ),
      ),
      ZionBrandMotionKeyframe(progress: 1, pose: _loaderPausedPose),
    ],
  ),
  ZionBrandMotionVariants.onboarding: ZionBrandMotionSpec(
    variant: ZionBrandMotionVariants.onboarding,
    duration: Duration(milliseconds: 900),
    settleDuration: Duration(milliseconds: 2400),
    loop: false,
    reducedMotionPolicy: ZionBrandReducedMotionPolicy.settled,
    pausedPose: _settledPose,
    reducedMotionPose: _settledPose,
    keyframes: [
      ZionBrandMotionKeyframe(
        progress: 0,
        pose: ZionBrandMotionPose(
          opacity: 0,
          scale: 0.92,
          translateY: 14.4,
          glowBlur: 0,
          glowOpacity: 0,
        ),
      ),
      ZionBrandMotionKeyframe(
        progress: 0.28,
        pose: ZionBrandMotionPose(
          opacity: 1,
          scale: 1.015,
          translateY: -4.48,
          glowBlur: 0.85,
          glowOpacity: 0.2,
        ),
      ),
      ZionBrandMotionKeyframe(
        progress: 0.62,
        pose: ZionBrandMotionPose(
          opacity: 1,
          scale: 0.995,
          translateY: 1.28,
          glowBlur: 0.55,
          glowOpacity: 0.16,
        ),
      ),
      ZionBrandMotionKeyframe(
        progress: 1,
        pose: ZionBrandMotionPose(
          opacity: 1,
          scale: 1,
          translateY: 0,
          glowBlur: 0.4,
          glowOpacity: 0.12,
        ),
      ),
    ],
  ),
  ZionBrandMotionVariants.liveness: ZionBrandMotionSpec(
    variant: ZionBrandMotionVariants.liveness,
    duration: Duration(milliseconds: 1400),
    loop: true,
    reducedMotionPolicy: ZionBrandReducedMotionPolicy.staticMark,
    pausedPose: _livenessPausedPose,
    reducedMotionPose: _livenessReducedMotionPose,
    keyframes: [
      ZionBrandMotionKeyframe(
        progress: 0,
        pose: ZionBrandMotionPose(
          opacity: 0.62,
          scale: 0.94,
          translateY: 0,
          glowBlur: 0.15,
          glowOpacity: 0.05,
        ),
      ),
      ZionBrandMotionKeyframe(
        progress: 0.5,
        pose: ZionBrandMotionPose(
          opacity: 1,
          scale: 1,
          translateY: 0,
          glowBlur: 0.55,
          glowOpacity: 0.18,
        ),
      ),
      ZionBrandMotionKeyframe(progress: 1, pose: _livenessPausedPose),
    ],
  ),
  ZionBrandMotionVariants.pairing: ZionBrandMotionSpec(
    variant: ZionBrandMotionVariants.pairing,
    duration: Duration(milliseconds: 1800),
    loop: false,
    reducedMotionPolicy: ZionBrandReducedMotionPolicy.settled,
    pausedPose: _settledPose,
    reducedMotionPose: _settledPose,
    keyframes: [
      ZionBrandMotionKeyframe(
        progress: 0,
        pose: ZionBrandMotionPose(
          opacity: 0.86,
          scale: 0.98,
          translateY: 0,
          glowBlur: 0.1,
          glowOpacity: 0.04,
        ),
      ),
      ZionBrandMotionKeyframe(
        progress: 0.38,
        pose: ZionBrandMotionPose(
          opacity: 1,
          scale: 1.02,
          translateY: 0,
          glowBlur: 0.8,
          glowOpacity: 0.22,
        ),
      ),
      ZionBrandMotionKeyframe(
        progress: 1,
        pose: ZionBrandMotionPose(
          opacity: 1,
          scale: 1,
          translateY: 0,
          glowBlur: 0.45,
          glowOpacity: 0.12,
        ),
      ),
    ],
  ),
  ZionBrandMotionVariants.agentEntrance: ZionBrandMotionSpec(
    variant: ZionBrandMotionVariants.agentEntrance,
    duration: Duration(milliseconds: 900),
    staggerDuration: Duration(milliseconds: 320),
    loop: false,
    reducedMotionPolicy: ZionBrandReducedMotionPolicy.settled,
    pausedPose: _settledPose,
    reducedMotionPose: _settledPose,
    keyframes: [
      ZionBrandMotionKeyframe(
        progress: 0,
        pose: ZionBrandMotionPose(
          opacity: 0,
          scale: 0.94,
          translateY: 11.2,
          glowBlur: 0,
          glowOpacity: 0,
        ),
      ),
      ZionBrandMotionKeyframe(
        progress: 0.55,
        pose: ZionBrandMotionPose(
          opacity: 1,
          scale: 1.01,
          translateY: -1.92,
          glowBlur: 0.55,
          glowOpacity: 0.16,
        ),
      ),
      ZionBrandMotionKeyframe(progress: 1, pose: _settledPose),
    ],
  ),
};

bool isZionBrandMotionVariant(String value) {
  return ZionBrandMotionVariants.values.contains(value);
}

ZionBrandMotionSpec zionBrandMotionSpecFor(String variant) {
  final spec = _zionBrandMotionSpecs[variant];
  if (spec == null) {
    throw ArgumentError.value(
      variant,
      'variant',
      'Expected one of ${ZionBrandMotionVariants.values.join(', ')}',
    );
  }
  return spec;
}

ZionBrandMotionAsset zionBrandMotionAssetFor({
  required String variant,
  required Brightness brightness,
}) {
  final normalizedVariant = zionBrandMotionSpecFor(variant).variant;

  return switch (normalizedVariant) {
    ZionBrandMotionVariants.loader ||
    ZionBrandMotionVariants.liveness ||
    ZionBrandMotionVariants.agentEntrance => const ZionBrandMotionAsset(
      path: ZionBrandAssets.zionMarkSvg,
      kind: ZionBrandMotionAssetKind.mark,
    ),
    ZionBrandMotionVariants.onboarding || ZionBrandMotionVariants.pairing =>
      ZionBrandMotionAsset(
        path: brightness == Brightness.dark
            ? ZionBrandAssets.sentraLockupLightSvg
            : ZionBrandAssets.sentraLockupDarkSvg,
        kind: ZionBrandMotionAssetKind.lockup,
      ),
    _ => throw ArgumentError.value(
      variant,
      'variant',
      'Expected one of ${ZionBrandMotionVariants.values.join(', ')}',
    ),
  };
}
