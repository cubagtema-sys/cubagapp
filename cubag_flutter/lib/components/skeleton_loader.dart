import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class SkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
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

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLoader(height: 160, borderRadius: 16),
            SizedBox(height: 24),
            SkeletonLoader(width: 150, height: 24),
            SizedBox(height: 16),
            SkeletonLoader(height: 100, borderRadius: 12),
            SizedBox(height: 16),
            SkeletonLoader(height: 100, borderRadius: 12),
            SizedBox(height: 24),
            SkeletonLoader(width: 150, height: 24),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: SkeletonLoader(height: 80, borderRadius: 12)),
                SizedBox(width: 12),
                Expanded(child: SkeletonLoader(height: 80, borderRadius: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ShimmerListTile extends StatelessWidget {
  const ShimmerListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          SkeletonLoader(width: 40, height: 40, borderRadius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(width: 160, height: 14),
                SizedBox(height: 6),
                SkeletonLoader(width: 100, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
