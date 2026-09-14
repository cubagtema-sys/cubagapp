import 'package:flutter/material.dart';

/// Reusable CUBAG logo widget.
/// Shows the real logo.jpeg asset with a fallback orange "C" icon if missing.
class AppLogo extends StatelessWidget {
  final double size;
  final double borderRadius;
  final bool showShadow;

  const AppLogo({
    super.key,
    this.size = 56,
    this.borderRadius = 14,
    this.showShadow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(50),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          'assets/images/logo.jpeg',
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => Container(
            color: const Color(0xFFFF5000),
            alignment: Alignment.center,
            child: Text(
              'C',
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
