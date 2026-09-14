import 'package:flutter/material.dart';

Widget buildIframe(String mmsi) {
  return const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.map, size: 48, color: Colors.grey),
        SizedBox(height: 12),
        Text(
          'Map view not supported on this platform.',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    ),
  );
}
