import 'package:flutter/material.dart';

/// The silver Zion mark and product label, without a square app-icon backdrop.
class OnboardingWordmark extends StatelessWidget {
  /// Optional label tint; the metallic mark is never recolored.
  final Color? color;

  /// Creates the Zion welcome identity.
  const OnboardingWordmark({super.key, this.color});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Zion',
    image: true,
    child: ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CustomPaint(
              size: Size(112, 112),
              painter: _ZionMetallicMarkPainter(),
            ),
            const SizedBox(height: 18),
            Text(
              'ZION',
              style: TextStyle(
                fontFamily: 'Michroma',
                fontSize: 34,
                fontWeight: FontWeight.w400,
                letterSpacing: 5,
                color: color ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The same two-slash geometry as the installer, drawn on transparency.
class _ZionMetallicMarkPainter extends CustomPainter {
  const _ZionMetallicMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);

    final top = Path()
      ..moveTo(16, 30)
      ..lineTo(32, 12)
      ..lineTo(52, 12)
      ..lineTo(36, 30)
      ..close();
    final bottom = Path()
      ..moveTo(12, 52)
      ..lineTo(28, 34)
      ..lineTo(48, 34)
      ..lineTo(32, 52)
      ..close();

    void drawSlash(Path path, List<Color> silver) {
      final bounds = path.getBounds();
      canvas.drawShadow(path, const Color(0x88000000), 4, false);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: silver,
          ).createShader(bounds),
      );
    }

    drawSlash(top, const [
      Color(0xFFFFFFFF),
      Color(0xFFD7D7D9),
      Color(0xFF929295),
    ]);
    drawSlash(bottom, const [
      Color(0xFFC5C5C8),
      Color(0xFF818184),
      Color(0xFF4E4E50),
    ]);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
