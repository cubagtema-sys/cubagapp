import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/skeleton_loader.dart';
import '../services/api_service.dart';
import '../components/cors_image_widget.dart';
import '../utils/app_logger.dart';
import '../utils/app_colors.dart';

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
  final _newsSearchCtrl = TextEditingController();
  String _newsFilterSource = 'all';
  final _calcAmountCtrl = TextEditingController(text: '1000');
  String _calcCurrency = 'USD';
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
    _newsSearchCtrl.dispose();
    _calcAmountCtrl.dispose();
    super.dispose();
  }

  List<_Article> get _filteredArticles {
    final q = _newsSearchCtrl.text.trim().toLowerCase();
    final src = _newsFilterSource.toLowerCase();
    return _articles.where((a) {
      if (src != 'all' && a.source.toLowerCase() != src) return false;
      if (q.isNotEmpty &&
          !a.title.toLowerCase().contains(q) &&
          !a.source.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
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
                  style: TextStyle(
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
              style: TextStyle(color: Colors.white, fontSize: 13),
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
    final cardBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final borderColor = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final textColor = isDark ? Colors.white : const Color(0xFF1F1612);
    final subTextColor = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

    return AppLayout(
      title: 'Intelligence Hub',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 1050;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Page Header
                  AdminHeader(
                    title: 'Maritime Intelligence Hub',
                    subtitle: 'Global maritime news feeds, port telemetry, and daily customs FX parity rates.',
                    actions: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : const Color(0xFF334155),
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          _load();
                          _loadIntelligence();
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: Text('Refresh All', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left 62%: Maritime News Feed & Telemetry
                        Expanded(
                          flex: 62,
                          child: _buildNewsSection(isDark, cardBg, borderColor, textColor, subTextColor),
                        ),
                        const SizedBox(width: 20),
                        // Right 38%: Customs FX Desk & Rate Calculator
                        Expanded(
                          flex: 38,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildForexManagerCard(isDark, cardBg, borderColor, textColor, subTextColor),
                              const SizedBox(height: 18),
                              _buildDutyCalculatorCard(isDark, cardBg, borderColor, textColor, subTextColor),
                              const SizedBox(height: 18),
                              _buildGuidanceCard(isDark, cardBg, borderColor, textColor, subTextColor),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildForexManagerCard(isDark, cardBg, borderColor, textColor, subTextColor),
                        const SizedBox(height: 16),
                        _buildDutyCalculatorCard(isDark, cardBg, borderColor, textColor, subTextColor),
                        const SizedBox(height: 20),
                        _buildNewsSection(isDark, cardBg, borderColor, textColor, subTextColor),
                      ],
                    ),
                  const SizedBox(height: 32),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNewsSection(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final filtered = _filteredArticles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connected sources pill bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A0F0A).withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                'Connected Sources:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildSourceFilterChip('All Sources', 'all', _newsFilterSource == 'all', isDark, borderColor, textColor),
                      ..._feedSources.map((s) {
                        final name = s['source'] as String;
                        final color = Color(s['color'] as int);
                        final isSel = _newsFilterSource.toLowerCase() == name.toLowerCase();
                        return _buildSourceFilterChip(name, name, isSel, isDark, borderColor, textColor, sourceColor: color);
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Search & Filter Header
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _newsSearchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 13.5, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search maritime bulletins, shipping lines, port news...',
                    hintStyle: TextStyle(fontSize: 12.5, color: subTextColor),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: subTextColor),
                    filled: true,
                    fillColor: cardBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kOrange, width: 1.2)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                    suffixIcon: _newsSearchCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.close_rounded, size: 14),
                            onPressed: () {
                              _newsSearchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _kOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${filtered.length} Feed Items',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentOrangeText),
                  ),
                  if (_lastUpdated.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '• $_lastUpdated',
                      style: TextStyle(fontSize: 11, color: _kOrange.withValues(alpha: 0.8)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Articles List
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
                              SkeletonLoader(width: 70, height: 14, borderRadius: 4),
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
        else if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.feed_outlined, color: subTextColor, size: 36),
                  const SizedBox(height: 12),
                  Text('No articles match criteria', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Try adjusting your search terms or filter selection.', style: TextStyle(color: subTextColor, fontSize: 12.5)),
                ],
              ),
            ),
          )
        else
          Column(
            children: filtered.map((a) => _buildArticleCard(a, isDark, cardBg, borderColor, textColor, subTextColor)).toList(),
          ),
      ],
    );
  }

  Widget _buildSourceFilterChip(
    String label,
    String key,
    bool isSel,
    bool isDark,
    Color borderColor,
    Color textColor, {
    Color? sourceColor,
  }) {
    final activeCol = sourceColor ?? _kOrange;
    return InkWell(
      onTap: () => setState(() => _newsFilterSource = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? activeCol.withValues(alpha: isDark ? 0.25 : 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSel ? activeCol : borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
            color: isSel ? (isDark ? Colors.white : activeCol) : (isDark ? Colors.white70 : const Color(0xFF475569)),
          ),
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
      margin: const EdgeInsets.only(bottom: 12),
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
                        color: isDark ? const Color(0xFF381F15) : const Color(0xFFF1F5F9),
                        child: const Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange),
                          ),
                        ),
                      ),
                      errorWidget: Container(
                        width: 76,
                        height: 76,
                        color: isDark ? const Color(0xFF381F15) : const Color(0xFFF1F5F9),
                        child: Icon(Icons.newspaper_rounded, color: subTextColor.withValues(alpha: 0.5), size: 20),
                      ),
                    )
                  : Container(
                      width: 76,
                      height: 76,
                      color: isDark ? const Color(0xFF381F15) : const Color(0xFFF1F5F9),
                      child: Center(
                        child: Icon(Icons.article_outlined, color: a.sourceColor.withValues(alpha: 0.7), size: 24),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: a.sourceColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: a.sourceColor.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          a.source,
                          style: TextStyle(
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
                          style: TextStyle(fontSize: 11.5, color: subTextColor, fontWeight: FontWeight.w500),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        color: subTextColor,
                        tooltip: 'Copy link',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: a.link));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Article link copied to clipboard'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, size: 14),
                        color: _kOrange,
                        tooltip: 'Read full article',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          if (a.link.isNotEmpty) {
                            final uri = Uri.parse(a.link);
                            if (await canLaunchUrl(uri)) {
                              launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    a.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: textColor,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDutyCalculatorCard(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final rateStr = _forex[_calcCurrency] ?? '15.45';
    final rate = double.tryParse(rateStr) ?? 15.45;
    final amount = double.tryParse(_calcAmountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
    final converted = amount * rate;

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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.calculate_rounded, color: Color(0xFF10B981), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customs Duty FX Estimator', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: textColor)),
                    Text('Instant tariff conversion to Ghana Cedis (GHS)', style: TextStyle(fontSize: 11.5, color: subTextColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _calcAmountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                  decoration: InputDecoration(
                    labelText: 'Invoice / CIF Value',
                    labelStyle: TextStyle(fontSize: 12, color: subTextColor),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFFAF6F0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _calcCurrency,
                  decoration: InputDecoration(
                    labelText: 'Currency',
                    labelStyle: TextStyle(fontSize: 12, color: subTextColor),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFFAF6F0),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                    DropdownMenuItem(value: 'GBP', child: Text('GBP (£)')),
                    DropdownMenuItem(value: 'CNY', child: Text('CNY (¥)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _calcCurrency = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ESTIMATED CUSTOMS VALUE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF10B981), letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    SelectableText(
                      'GH₵ ${converted.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                    Text('@ GHS $rateStr / $_calcCurrency', style: TextStyle(fontSize: 11, color: subTextColor)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  color: const Color(0xFF10B981),
                  tooltip: 'Copy converted amount',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: 'GH₵ ${converted.toStringAsFixed(2)}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Calculated customs value copied'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidanceCard(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF3B82F6)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bank of Ghana & ICUMS Parity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: textColor)),
                const SizedBox(height: 3),
                Text(
                  'Customs exchange rates must be synchronized daily at 09:00 GMT in compliance with GRA Customs Division tariff schedules.',
                  style: TextStyle(fontSize: 11.5, color: subTextColor, height: 1.35),
                ),
              ],
            ),
          ),
        ],
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                    Text(
                      'Exchange rates published live to member portal & dashboard calculations.',
                      style: TextStyle(
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
                    style: TextStyle(
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
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                code,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color,
                ),
              ),
              const Spacer(),
              Text(
                'GHS',
                style: TextStyle(
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
              style: TextStyle(
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
                fillColor: isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF3D261C)
                        : const Color(0xFFE8DED6),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF3D261C)
                        : const Color(0xFFE8DED6),
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
