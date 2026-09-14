part of '../admin_surveys_page.dart';

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color borderColor;
  const _RingPainter(this.progress, this.color, this.borderColor);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) - 12;
    const strokeW = 14.0;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0, 1),
        false,
        Paint()
          ..shader =
              SweepGradient(
                colors: [color.withValues(alpha: 0.5), color],
                startAngle: -math.pi / 2,
                endAngle: 2 * math.pi - math.pi / 2,
              ).createShader(
                Rect.fromCircle(center: Offset(cx, cy), radius: radius),
              )
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
