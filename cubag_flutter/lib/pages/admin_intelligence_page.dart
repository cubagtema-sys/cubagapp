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

const _feedSources = [
  {
    'source': 'gCaptain',
    'color': 0xFFFF5000,
  },
  {
    'source': 'Hellenic Shipping',
    'color': 0xFF10b981,
  },
  {
    'source': 'Splash247',
    'color': 0xFF0284c7,
  },
  {
    'source': 'Ship Technology',
    'color': 0xFFe11d48,
  },
  {
    'source': 'FreightWaves',
    'color': 0xFF6366f1,
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
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Customs FX rates saved & published successfully!',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
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
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
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
        : const Color(0xFF64748b);

    return AppLayout(
      title: 'Intelligence Hub',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            AdminHeader(
              title: 'Maritime Intelligence Hub',
              subtitle:
                  'Global maritime news feeds, port telemetry, and daily customs FX rates.',
              actions: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : const Color(0xFF334155),
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    _load();
                    _loadIntelligence();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(
                    'Refresh All',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Connected sources pill bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A0F0A).withValues(alpha: 0.5)
                    : const Color(0xFFf8fafc),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10b981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Connected Feeds:',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _feedSources.map((s) {
                          final color = Color(s['color'] as int);
                          return Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: color.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  s['source'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Forex Currency Rates Card
            _buildForexManagerCard(
              isDark,
              cardBg,
              borderColor,
              textColor,
              subTextColor,
            ),
            const SizedBox(height: 24),

            // News Feed Section Header
            Row(
              children: [
                const Icon(
                  Icons.directions_boat_filled_rounded,
                  color: _kOrange,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Maritime Feed',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.5,
                    color: textColor,
                  ),
                ),
                if (_articles.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_articles.length}',
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _kOrange,
                      ),
                    ),
                  ),
                ],
                if (_lastUpdated.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• updated $_lastUpdated',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      color: subTextColor,
                    ),
                  ),
                ],
                const Spacer(),
                if (!_loading)
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Refresh news',
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: subTextColor,
                    ),
                    onPressed: _load,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Feed List or Loaders
            if (_loading)
              Column(
                children: List.generate(
                  4,
                  (index) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonLoader(width: 72, height: 72, borderRadius: 8),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SkeletonLoader(
                                    width: 70,
                                    height: 14,
                                    borderRadius: 4,
                                  ),
                                  const SizedBox(width: 8),
                                  SkeletonLoader(width: 50, height: 10),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SkeletonLoader(height: 14),
                              const SizedBox(height: 5),
                              SkeletonLoader(width: 160, height: 14),
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
                  vertical: 36,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF4D2D20)
                              : const Color(0xFFf1f5f9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.wifi_off_rounded,
                          color: subTextColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'News feed temporarily unavailable',
                        style: GoogleFonts.outfit(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Unable to connect to live syndication endpoints.',
                        style: GoogleFonts.outfit(
                          color: subTextColor,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 14),
                        label: Text(
                          'Try Again',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (a.link.isNotEmpty) {
              final uri = Uri.parse(a.link);
              if (await canLaunchUrl(uri)) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            }
          },
          borderRadius: BorderRadius.circular(12),
          hoverColor: _kOrange.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: a.thumbnail.isNotEmpty
                      ? CorsImageWidget(
                          url: a.thumbnail,
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                          placeholder: Container(
                            width: 76,
                            height: 76,
                            color: isDark
                                ? const Color(0xFF381F15)
                                : const Color(0xFFf1f5f9),
                            child: const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _kOrange,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: Container(
                            width: 76,
                            height: 76,
                            color: isDark
                                ? const Color(0xFF381F15)
                                : const Color(0xFFf1f5f9),
                            child: Icon(
                              Icons.newspaper_rounded,
                              color: subTextColor.withValues(alpha: 0.5),
                              size: 20,
                            ),
                          ),
                        )
                      : Container(
                          width: 76,
                          height: 76,
                          color: isDark
                              ? const Color(0xFF381F15)
                              : const Color(0xFFf1f5f9),
                          child: Center(
                            child: Icon(
                              Icons.article_outlined,
                              color: a.sourceColor.withValues(alpha: 0.7),
                              size: 24,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 14),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: a.sourceColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: a.sourceColor.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              a.source,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: a.sourceColor,
                              ),
                            ),
                          ),
                          if (a.pubDate.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(a.pubDate),
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: subTextColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Icon(
                            Icons.arrow_outward_rounded,
                            size: 13,
                            color: subTextColor.withValues(alpha: 0.7),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        a.title,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          color: textColor,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF3b82f6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.currency_exchange_rounded,
                  color: Color(0xFF3b82f6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Official Customs FX Rates (GHS)',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                    Text(
                      'Exchange rates published live to member portal & dashboard calculations.',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (_forexLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3b82f6),
                  ),
                )
              else
                IconButton(
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: subTextColor,
                  ),
                  tooltip: 'Reload rates',
                  onPressed: _loadIntelligence,
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (_forexLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF3b82f6),
                  ),
                ),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 550;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 4 : 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: isWide ? 2.1 : 2.2,
                  children: [
                    _buildCurrencyInput(
                      '\$',
                      'USD',
                      'US Dollar',
                      _usdCtrl,
                      const Color(0xFF3b82f6),
                      isDark,
                    ),
                    _buildCurrencyInput(
                      '€',
                      'EUR',
                      'Euro',
                      _eurCtrl,
                      const Color(0xFF10b981),
                      isDark,
                    ),
                    _buildCurrencyInput(
                      '£',
                      'GBP',
                      'British Pound',
                      _gbpCtrl,
                      const Color(0xFF8b5cf6),
                      isDark,
                    ),
                    _buildCurrencyInput(
                      '¥',
                      'CNY',
                      'Chinese Yuan',
                      _cnyCtrl,
                      const Color(0xFFf59e0b),
                      isDark,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: _forexSaving ? null : _saveForex,
                  icon: _forexSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text(
                    _forexSaving ? 'Saving...' : 'Save Rates',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3b82f6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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
    String code,
    String name,
    TextEditingController ctrl,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A0F0A).withValues(alpha: 0.5)
            : const Color(0xFFf8fafc),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  symbol,
                  style: GoogleFonts.outfit(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                code,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                'GHS',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : const Color(0xFF64748b),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
                color: isDark ? Colors.white : const Color(0xFF1A0F0A),
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                hintText: '0.00',
                filled: true,
                fillColor: isDark ? const Color(0xFF281710) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF4D2D20)
                        : const Color(0xFFcbd5e1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF4D2D20)
                        : const Color(0xFFcbd5e1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: color, width: 1.2),
                ),
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
    try {
      final clean = httpDate
          .replaceFirst(RegExp(r'^[A-Za-z]+, '), '')
          .replaceFirst(RegExp(r' \+?\d{4}$'), '')
          .replaceFirst(RegExp(r' [A-Z]{2,4}$'), '')
          .trim();
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
