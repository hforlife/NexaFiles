import 'package:flutter/material.dart';

/// NexaFiles brand mark (logo "Dossier N"): a white folder carrying the
/// brand N on the indigo → violet gradient. Same shapes as the launcher icon.
class NexaLogo extends StatelessWidget {
  const NexaLogo({super.key, this.size = 40});
  final double size;

  static const brandStart = Color(0xFF6366F1), brandEnd = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'NexaFiles',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _LogoPainter()),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 512 × 512 grid, like the icon source.
    canvas.scale(size.width / 512, size.height / 512);
    const gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [NexaLogo.brandStart, NexaLogo.brandEnd],
    );
    final square = const Rect.fromLTWH(0, 0, 512, 512);
    canvas.drawRRect(
      RRect.fromRectAndRadius(square, const Radius.circular(112)),
      Paint()..shader = gradient.createShader(square),
    );
    canvas.translate(96, 104);
    canvas.scale(2.2);
    // Folder back with its tab.
    final back = Path()
      ..moveTo(0, 18)
      ..quadraticBezierTo(0, 6, 12, 6)
      ..lineTo(46, 6)
      ..lineTo(58, 18)
      ..lineTo(116, 18)
      ..quadraticBezierTo(128, 18, 128, 30)
      ..lineTo(128, 106)
      ..quadraticBezierTo(128, 118, 116, 118)
      ..lineTo(12, 118)
      ..quadraticBezierTo(0, 118, 0, 106)
      ..close();
    canvas.drawPath(back, Paint()..color = Colors.white.withValues(alpha: .28));
    // Folder front.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 36, 128, 82),
        const Radius.circular(12),
      ),
      Paint()..color = Colors.white,
    );
    // The N.
    final n = Path()
      ..moveTo(42, 102)
      ..lineTo(42, 56)
      ..lineTo(86, 102)
      ..lineTo(86, 56);
    canvas.drawPath(
      n,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = gradient.createShader(const Rect.fromLTWH(42, 56, 44, 46)),
    );
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}
