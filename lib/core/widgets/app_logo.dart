import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({this.size = 80, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(
          color: AppColors.white.withValues(alpha: 0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.40),
            blurRadius: size * 0.35,
            spreadRadius: size * 0.02,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _InventraMarkPainter(),
      ),
    );
  }
}

class _InventraMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double sw = size.width;
    final double sh = size.height;

    // ── Spine ──
    canvas.drawLine(
      Offset(sw * 0.24, sh * 0.28),
      Offset(sw * 0.24, sh * 0.76),
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55)
        ..strokeWidth = sw * 0.055
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    final barPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = sw * 0.115
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // ── Bar 1 — longest ──
    canvas.drawLine(
      Offset(sw * 0.24, sh * 0.30),
      Offset(sw * 0.78, sh * 0.30),
      barPaint,
    );

    // ── Bar 2 — medium ──
    canvas.drawLine(
      Offset(sw * 0.24, sh * 0.52),
      Offset(sw * 0.64, sh * 0.52),
      barPaint,
    );

    // ── Bar 3 — short ──
    canvas.drawLine(
      Offset(sw * 0.24, sh * 0.74),
      Offset(sw * 0.50, sh * 0.74),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
