import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class ShimmerListTile extends StatelessWidget {
  const ShimmerListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          const ShimmerLoader(width: 40, height: 40, borderRadius: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ShimmerLoader(width: double.infinity, height: 14),
                const SizedBox(height: 8),
                const ShimmerLoader(width: 100, height: 12),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const ShimmerLoader(width: 60, height: 20, borderRadius: 20),
        ],
      ),
    );
  }
}

class ShimmerGridCard extends StatelessWidget {
  const ShimmerGridCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ShimmerLoader(width: 36, height: 36, borderRadius: 18),
              const Spacer(),
              const ShimmerLoader(width: 50, height: 16, borderRadius: 10),
            ],
          ),
          const SizedBox(height: 12),
          const ShimmerLoader(width: double.infinity, height: 14),
          const SizedBox(height: 6),
          const ShimmerLoader(width: 120, height: 12),
          const SizedBox(height: 12),
          const ShimmerLoader(width: double.infinity, height: 12),
          const Spacer(),
          Row(
            children: [
              const Expanded(
                child: ShimmerLoader(
                  width: double.infinity,
                  height: 36,
                  borderRadius: 12,
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: ShimmerLoader(
                  width: double.infinity,
                  height: 36,
                  borderRadius: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
