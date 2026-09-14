import 'package:flutter/material.dart';

Widget buildDocPreview(String url, String viewKey) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.preview_rounded, size: 48, color: Color(0xFF6b6375)),
          const SizedBox(height: 8),
          Text(
            'Preview not available on this platform.',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    ),
  );
}
