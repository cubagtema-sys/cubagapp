import 'package:flutter/material.dart';

/// Shown when a page's data fetch fails (network error, server timeout, etc.)
/// Provides a visible retry button so the user can try again.
class FetchErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;

  const FetchErrorView({super.key, required this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Colors.orange,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load data',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              message ??
                  'The server may be starting up.\nPlease wait a moment and try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 15),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text(
                'Retry',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
