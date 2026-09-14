import 'package:flutter/material.dart';

class TrendLinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  TrendLinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();

    final double dx = size.width / (data.length - 1);
    const double maxVal = 100.0;
    const double minVal = 0.0;
    const double range = maxVal - minVal;

    double getRawY(double val) {
      final pct = (val - minVal) / range;
      // Clamp to size bounds
      final y = size.height - (pct * size.height);
      return y.clamp(0.0, size.height);
    }

    // Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw lines at 0%, 50%, and 100%
    canvas.drawLine(
      Offset(0, getRawY(100)),
      Offset(size.width, getRawY(100)),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, getRawY(50)),
      Offset(size.width, getRawY(50)),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, getRawY(0)),
      Offset(size.width, getRawY(0)),
      gridPaint,
    );

    path.moveTo(0, getRawY(data[0]));
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, getRawY(data[0]));

    for (int i = 1; i < data.length; i++) {
      final x = i * dx;
      final y = getRawY(data[i]);
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw dots and glow
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final outerDotPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final offset = Offset(i * dx, getRawY(data[i]));
      canvas.drawCircle(offset, 6.0, outerDotPaint);
      canvas.drawCircle(offset, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TrendLinePainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}

class TrendLineWidget extends StatelessWidget {
  final List<double> points;
  final Color color;
  final double height;

  const TrendLineWidget({
    super.key,
    required this.points,
    required this.color,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        height: height,
        alignment: Alignment.center,
        child: const Text(
          'No trend data available',
          style: TextStyle(color: Colors.grey, fontSize: 15),
        ),
      );
    }

    // Ensure we have at least 2 points to draw
    final pts = points.length == 1 ? [points[0], points[0]] : points;

    return Column(
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: TrendLinePainter(pts, color)),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'First Rec',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Latest Rating',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
