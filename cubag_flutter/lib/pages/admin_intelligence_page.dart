import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/skeleton_loader.dart';
import '../services/api_service.dart';
import '../components/cors_image_widget.dart';
import '../utils/app_logger.dart';

const _kOrange = Color(0xFFFF5000);

// Mirror the exact same 6 feed sources from React
const _feedSources = [
  {
    'url': 'https://gcaptain.com/feed/',
    'source': 'gCaptain',
    'color': 0xFFFF5000,
  },
  {
    'url': 'https://www.hellenicshippingnews.com/feed/',
    'source': 'Hellenic Shipping',
    'color': 0xFF1a6b3c,
  },
  {
    'url': 'https://splash247.com/feed/',
    'source': 'Splash247',
    'color': 0xFF0066cc,
  },
  {
    'url': 'https://www.ship-technology.com/feed/',
    'source': 'Ship Technology',
    'color': 0xFFc0392b,
  },
  {
    'url': 'https://www.freightwaves.com/news/feed',
    'source': 'FreightWaves',
    'color': 0xFF003580,
  },
];

class AdminIntelligencePage extends StatefulWidget {
  const AdminIntelligencePage({super.key});
  @override
  State<AdminIntelligencePage> createState() => _State();
}

class _Article {
  final String title, link, pubDate, source, thumbnail;
  final Color sourceColor;

  const _Article({
    required this.title,
    required this.link,
    required this.pubDate,
    required this.source,
    required this.thumbnail,
    required this.sourceColor,
  });
}

class _State extends State<AdminIntelligencePage> {
  final _api = ApiService();
  bool _loading = true;
  List<_Article> _articles = [];
  String _lastUpdated = '';

  bool _forexLoading = true;
  bool _forexSaving = false;
  Map<String, String> _forex = {
    'USD': '15.45',
    'EUR': '16.80',
    'GBP': '19.50',
    'CNY': '2.15',
  };
  final _usdCtrl = TextEditingController();
  final _eurCtrl = TextEditingController();
  final _gbpCtrl = TextEditingController();
  final _cnyCtrl = TextEditingController();
  Map<String, dynamic> _fullIntelligenceData = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadIntelligence();
  }

  @override
  void dispose() {
    _usdCtrl.dispose();
    _eurCtrl.dispose();
    _gbpCtrl.dispose();
    _cnyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIntelligence() async {
    setState(() => _forexLoading = true);
    try {
      final res = await _api.getPublic('intelligence');
      if (res != null && res is Map) {
        _fullIntelligenceData = Map<String, dynamic>.from(res);
        final forexMap = res['forex'];
        if (forexMap != null && forexMap is Map) {
          _forex = {
            'USD': forexMap['USD']?.toString() ?? '15.45',
            'EUR': forexMap['EUR']?.toString() ?? '16.80',
            'GBP': forexMap['GBP']?.toString() ?? '19.50',
            'CNY': forexMap['CNY']?.toString() ?? '2.15',
          };
        }
      }
    } catch (e, st) {
      AppLogger.error('admin_intelligence_page', e, st);
    }
    if (mounted) {
      _usdCtrl.text = _forex['USD'] ?? '15.45';
      _eurCtrl.text = _forex['EUR'] ?? '16.80';
      _gbpCtrl.text = _forex['GBP'] ?? '19.50';
      _cnyCtrl.text = _forex['CNY'] ?? '2.15';
      setState(() => _forexLoading = false);
    }
  }

  Future<void> _saveForex() async {
    setState(() => _forexSaving = true);
    try {
      if (_fullIntelligenceData.isEmpty) {
        final res = await _api.getPublic('intelligence');
        if (res != null && res is Map) {
          _fullIntelligenceData = Map<String, dynamic>.from(res);
        }
      }

      _fullIntelligenceData['forex'] = {
        'USD': _usdCtrl.text.trim(),
        'EUR': _eurCtrl.text.trim(),
        'GBP': _gbpCtrl.text.trim(),
        'CNY': _cnyCtrl.text.trim(),
      };

      await _api.post('intelligence', data: _fullIntelligenceData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live currency rates updated successfully across user portal!',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10b981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update currency rates: $e',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFef4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _forexSaving = false);
      }
    }
  }

  Future<void> _load({bool isRetry = false}) async {
    setState(() {
      _loading = true;
      _articles = [];
    });

    try {
      final res = await _api.getPublic('news/global');
      if (res is List) {
        final List<_Article> parsed = [];
        for (final item in res) {
          if (item is Map) {
            final title = item['title']?.toString() ?? '';
            final link = item['link']?.toString() ?? '';
            final pubDate = item['pubDate']?.toString() ?? '';
            final source = item['source']?.toString() ?? '';
            final thumbnail = item['thumbnail']?.toString() ?? '';
            final colorHexStr = item['sourceColor']?.toString() ?? '#3b82f6';

            // Parse color
            Color color;
            try {
              final cleanHex = colorHexStr.replaceAll('#', '');
              color = Color(int.parse('FF$cleanHex', radix: 16));
            } catch (_) {
              color = const Color(0xFF3b82f6);
            }

            parsed.add(
              _Article(
                title: title,
                link: link,
                pubDate: pubDate,
                source: source,
                thumbnail: thumbnail,
                sourceColor: color,
              ),
            );
          }
        }
        if (mounted) {
          setState(() {
            _articles = parsed;
            _loading = false;
            _lastUpdated = TimeOfDay.now().format(context);
          });

          // Auto-retry once if result was only mock/empty data (server cache warming up)
          if (!isRetry && parsed.length <= 2) {
            await Future.delayed(const Duration(seconds: 4));
            if (mounted) _load(isRetry: true);
          }
          return;
        }
      }
    } catch (e, st) {
      AppLogger.error('admin_intelligence_page', e, st);
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
      // Auto-retry once after brief delay if network failed
      if (!isRetry) {
        await Future.delayed(const Duration(seconds: 4));
        if (mounted) _load(isRetry: true);
      }
    }
  }

  String _formatDate(String pubDate) {
    try {
      final dt = HttpDate.parse(pubDate);
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final monthStr = months[(dt.month - 1).clamp(0, 11)];
      return '$monthStr ${dt.day}, ${dt.year}';
    } catch (_) {
      return pubDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    final textColor = isDark
        ? const Color(0xFFf8fafc)
        : const Color(0xFF1A0F0A);
    final subTextColor = isDark
        ? const Color(0xFF94a3b8)
        : const Color(0xFF475569);

    return AppLayout(
      title: 'Intelligence Hub',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminHeader(
              title: 'Maritime Intelligence Hub',
              subtitle:
                  'Live global maritime news syndication, port traffic telemetry, and daily customs FX conversion rates.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAdminOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    _load();
                    _loadIntelligence();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    'Refresh Feeds',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Status Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A0F0A).withValues(alpha: 0.4)
                    : const Color(0xFFf0fdf4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(
                    0xFF10b981,
                  ).withValues(alpha: isDark ? 0.3 : 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.anchor_rounded,
                        color: Color(0xFF10b981),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Maritime Intelligence Active',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: const Color(0xFF10b981),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'The Intelligence Hub is directly connected to 5 maritime and customs news networks — '
                    'gCaptain, Hellenic Shipping News, Splash247, Ship Technology, and FreightWaves. '
                    'Live data is pulled 24/7 for all CUBAG members.',
                    style: GoogleFonts.outfit(
                      fontSize: 17,
                      color: isDark
                          ? const Color(0xFF94a3b8)
                          : const Color(0xFF281710).withValues(alpha: 0.8),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _feedSources.map((s) {
                      final color = Color(s['color'] as int);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: color.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              (s['source'] as String).toUpperCase(),
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: color,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Manual Currency Rates Management Section
            _buildForexManagerCard(
              isDark,
              cardBg,
              borderColor,
              textColor,
              subTextColor,
            ),
            const SizedBox(height: 24),

            // Feed header
            Row(
              children: [
                const Icon(
                  Icons.directions_boat_filled_rounded,
                  color: _kOrange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Maritime Feed',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: textColor,
                  ),
                ),
                if (_lastUpdated.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• updated $_lastUpdated',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      color: subTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const Spacer(),
                if (!_loading)
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF281710)
                          : Colors.grey.shade100,
                      border: Border.all(color: borderColor),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: 'Refresh feeds',
                      icon: Icon(
                        Icons.refresh,
                        size: 16,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      onPressed: _load,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Feed content
            if (_loading)
              Column(
                children: List.generate(
                  4,
                  (index) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonLoader(width: 90, height: 90, borderRadius: 12),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SkeletonLoader(
                                    width: 80,
                                    height: 18,
                                    borderRadius: 6,
                                  ),
                                  const SizedBox(width: 8),
                                  SkeletonLoader(width: 60, height: 12),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SkeletonLoader(height: 16),
                              const SizedBox(height: 6),
                              SkeletonLoader(width: 180, height: 16),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  SkeletonLoader(
                                    width: 100,
                                    height: 14,
                                    borderRadius: 4,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_articles.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 48,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.15 : 0.02,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF4D2D20)
                              : const Color(0xFFf1f5f9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.wifi_off_rounded,
                          color: subTextColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Feed temporarily unavailable.',
                        style: GoogleFonts.outfit(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'The server may still be warming up.',
                        style: GoogleFonts.outfit(
                          color: subTextColor,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(
                          'Try Again',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
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
              )
            else
              Column(
                children: _articles
                    .map(
                      (a) => _buildArticleCard(
                        a,
                        isDark,
                        cardBg,
                        borderColor,
                        textColor,
                        subTextColor,
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildArticleCard(
    _Article a,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return InkWell(
      onTap: () async {
        if (a.link.isNotEmpty) {
          final uri = Uri.parse(a.link);
          if (await canLaunchUrl(uri)) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Premium Image Container
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: a.thumbnail.isNotEmpty
                  ? CorsImageWidget(
                      url: a.thumbnail,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [
                                    const Color(0xFF281710),
                                    const Color(0xFF4D2D20),
                                  ]
                                : [Colors.grey.shade100, Colors.grey.shade200],
                          ),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kOrange,
                            ),
                          ),
                        ),
                      ),
                      errorWidget: Container(
                        width: 90,
                        height: 90,
                        color: isDark
                            ? const Color(0xFF4D2D20)
                            : const Color(0xFFf1f5f9),
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: subTextColor.withValues(alpha: 0.6),
                          size: 22,
                        ),
                      ),
                    )
                  : Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  const Color(0xFF281710),
                                  const Color(0xFF4D2D20),
                                ]
                              : [Colors.grey.shade50, Colors.grey.shade100],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.article_outlined,
                          color: a.sourceColor.withValues(alpha: 0.6),
                          size: 28,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 16),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source badge + date
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: a.sourceColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: a.sourceColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          a.source.toUpperCase(),
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: a.sourceColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (a.pubDate.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _formatDate(a.pubDate),
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              color: subTextColor,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    a.title,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 19,
                      color: textColor,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Read full article',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          color: _kOrange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_outward_rounded,
                        size: 14,
                        color: _kOrange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForexManagerCard(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3b82f6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.currency_exchange_rounded,
                  color: Color(0xFF3b82f6),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Official Currency Exchange Rates',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Set official exchange rates against Ghana Cedi (GHS). The rates configured here are automatically published across the member portal and dashboard.',
                      style: GoogleFonts.outfit(
                        fontSize: 16.5,
                        color: subTextColor,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (_forexLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3b82f6),
                  ),
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: subTextColor,
                  ),
                  tooltip: 'Reload rates',
                  onPressed: _loadIntelligence,
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (_forexLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF3b82f6)),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 4 : 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: isWide ? 1.7 : 2.2,
                  children: [
                    _buildCurrencyInput(
                      'USD (\$)',
                      'US Dollar / GHS',
                      _usdCtrl,
                      const Color(0xFF3b82f6),
                      isDark,
                    ),
                    _buildCurrencyInput(
                      'EUR (€)',
                      'Euro / GHS',
                      _eurCtrl,
                      const Color(0xFF10b981),
                      isDark,
                    ),
                    _buildCurrencyInput(
                      'GBP (£)',
                      'British Pound / GHS',
                      _gbpCtrl,
                      const Color(0xFF8b5cf6),
                      isDark,
                    ),
                    _buildCurrencyInput(
                      'CNY (¥)',
                      'Chinese Yuan / GHS',
                      _cnyCtrl,
                      const Color(0xFFf59e0b),
                      isDark,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: _forexSaving ? null : _saveForex,
                  icon: _forexSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    _forexSaving ? 'Saving Rates...' : 'Save Forex Rates',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3b82f6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrencyInput(
    String symbol,
    String label,
    TextEditingController ctrl,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A0F0A).withValues(alpha: 0.5)
            : const Color(0xFFf8fafc),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  symbol
                      .split(' ')
                      .last
                      .replaceAll('(', '')
                      .replaceAll(')', ''),
                  style: GoogleFonts.outfit(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                symbol.split(' ').first,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                'GHS',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: isDark ? Colors.white : const Color(0xFF281710),
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              hintText: '0.00',
              filled: true,
              fillColor: isDark ? const Color(0xFF281710) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF4D2D20)
                      : const Color(0xFFcbd5e1),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF4D2D20)
                      : const Color(0xFFcbd5e1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: color, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Simple HTTP date fallback
class HttpDate {
  static DateTime parse(String httpDate) {
    // RFC 2822: Mon, 02 Jun 2025 10:30:00 GMT
    // Strip day-of-week prefix and timezone suffix, then inject T between date and time
    try {
      final clean = httpDate
          .replaceFirst(RegExp(r'^[A-Za-z]+, '), '')
          .replaceFirst(RegExp(r' \+?\d{4}$'), '')
          .replaceFirst(RegExp(r' [A-Z]{2,4}$'), '')
          .trim();
      // e.g. "02 Jun 2025 10:30:00" -> split into date+time parts
      final parts = clean.split(' ');
      if (parts.length >= 4) {
        final months = {
          'Jan': 1,
          'Feb': 2,
          'Mar': 3,
          'Apr': 4,
          'May': 5,
          'Jun': 6,
          'Jul': 7,
          'Aug': 8,
          'Sep': 9,
          'Oct': 10,
          'Nov': 11,
          'Dec': 12,
        };
        final day = int.parse(parts[0]);
        final month = months[parts[1]] ?? 1;
        final year = int.parse(parts[2]);
        final timeParts = parts[3].split(':');
        final hour = int.parse(timeParts[0]);
        final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
        final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;
        return DateTime.utc(year, month, day, hour, minute, second);
      }
    } catch (e, st) {
      AppLogger.error('admin_intelligence_page', e, st);
    }
    return DateTime.now();
  }
}
