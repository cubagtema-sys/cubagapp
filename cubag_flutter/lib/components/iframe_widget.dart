import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'iframe_stub.dart'
    if (dart.library.html) 'iframe_web.dart'
    if (dart.library.io) 'iframe_mobile.dart' as platform;

class IframeWidget extends StatefulWidget {
  final String mmsi;
  final String? vesselName;
  final double? lat;
  final double? lon;
  final String? destination;
  final String? speed;

  const IframeWidget({
    super.key,
    required this.mmsi,
    this.vesselName,
    this.lat,
    this.lon,
    this.destination,
    this.speed,
  });

  @override
  State<IframeWidget> createState() => _IframeWidgetState();
}

class _IframeWidgetState extends State<IframeWidget> {
  void _openMarineTraffic() {
    final cleanMmsi = widget.mmsi.trim();
    if (cleanMmsi.isEmpty) return;
    final isNumeric = RegExp(r'^\d+$').hasMatch(cleanMmsi);
    final url = isNumeric
        ? 'https://www.marinetraffic.com/en/ais/details/ships/mmsi:$cleanMmsi'
        : 'https://www.marinetraffic.com/en/ais/index/search/all/keyword:$cleanMmsi';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B);
    const accentGreen = Color(0xFF10B981);

    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentGreen.withAlpha(isDark ? 80 : 120),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ── The Interactive Map Layer ──────────────────────────────
          Positioned.fill(
            child: platform.buildIframe(
              widget.mmsi,
              vesselName: widget.vesselName,
              lat: widget.lat,
              lon: widget.lon,
              destination: widget.destination,
              speed: widget.speed,
            ),
          ),

          // ── Top Glass HUD Header ──────────────────────────────────
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentGreen.withValues(alpha: 0.5),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: accentGreen,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accentGreen,
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'LIVE AIS MAP',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accentGreen,
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (widget.mmsi.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· MMSI ${widget.mmsi}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _openMarineTraffic,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white24,
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'MarineTraffic',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 11,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom Telemetry Badge ────────────────────────────────
          Positioned(
            bottom: 8,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.navigation_rounded,
                    size: 10,
                    color: Color(0xFF38BDF8),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'OpenSeaMap Nautical Data · Gulf of Guinea / Tema Sector',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF5F6B7E),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
