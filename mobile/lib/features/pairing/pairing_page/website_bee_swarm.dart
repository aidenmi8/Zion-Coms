part of '../pairing_page.dart';

class _WebsiteBeeSwarm extends HookWidget {
  final Size size;
  final ObjectRef<Offset?> pointer;

  const _WebsiteBeeSwarm({required this.size, required this.pointer});

  @override
  Widget build(BuildContext context) {
    final motion = useMemoized(() => _WebsiteBeeMotion(size));
    if (motion.size != size) {
      motion.resize(size);
      pointer.value = null;
    }
    final clock = useAnimationController(duration: const Duration(days: 1));
    final lifecycle = useAppLifecycleState();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final playing =
        !reducedMotion &&
        TickerMode.valuesOf(context).enabled &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    useEffect(() {
      if (!playing) return null;
      var previous = Duration.zero;
      var remainder = 0.0;
      void tick() {
        final now = clock.lastElapsedDuration ?? Duration.zero;
        // Fixed 60 Hz reproduces the site's per-frame damping on 60/120 Hz
        // phones. Cap catch-up after stalls; never simulate a background gap.
        remainder += ((now - previous).inMicroseconds / 1e6).clamp(0, 0.05);
        previous = now;
        while (remainder >= 1 / 60) {
          motion.advance(1 / 60, pointer.value);
          remainder -= 1 / 60;
        }
      }

      clock.addListener(tick);
      clock.repeat();
      return () {
        clock.removeListener(tick);
        clock.stop();
      };
    }, [clock, motion, playing]);

    return ClipRect(
      key: const Key('welcome-bee-flight-area'),
      child: Stack(
        children: [
          for (var index = 0; index < motion.bees.length; index++)
            AnimatedBuilder(
              animation: clock,
              child: Opacity(
                opacity: index.isOdd ? 0.03 : 0.02,
                child: const CustomPaint(
                  size: Size(46, 31),
                  painter: _WelcomeSlashPainter(),
                ),
              ),
              builder: (context, child) {
                final bee = motion.bees[index];
                final progress = (motion.elapsed / 1.05).clamp(0.0, 1.0);
                final entrance = reducedMotion
                    ? 1.0
                    : 1 - math.pow(1 - progress, 3).toDouble();
                final position = Offset.lerp(
                  bee.entrance,
                  bee.position,
                  entrance,
                )!;
                return Transform.translate(
                  key: ValueKey('welcome-bee-$index'),
                  offset: position,
                  child: Transform.rotate(angle: bee.rotation, child: child),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Transparent silver slashes keep the existing decorative motion without
/// repeating the square app icon across the welcome background.
class _WelcomeSlashPainter extends CustomPainter {
  const _WelcomeSlashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFA6A6A8);
    Path slash(double x, double y) => Path()
      ..moveTo(x + 8, y)
      ..lineTo(x + 24, y)
      ..lineTo(x + 8, y + 12)
      ..lineTo(x - 8, y + 12)
      ..close();
    canvas.drawPath(slash(12, 2), paint);
    canvas.drawPath(slash(20, 17), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
