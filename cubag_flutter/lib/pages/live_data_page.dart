import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../utils/intelligence_data.dart';

class LiveDataPage extends StatefulWidget {
  const LiveDataPage({super.key});

  @override
  State<LiveDataPage> createState() => _LiveDataPageState();
}

class _LiveDataPageState extends State<LiveDataPage> {
  final _api = ApiService();
  Map<String, String> _forex = {
    'USD': '—',
    'EUR': '—',
    'GBP': '—',
    'CNY': '—',
  };
  bool _forexLoading = true;
  bool _forexIsSample = false;
  String _forexUpdated = '';
  bool _newsLoading = true;
  List<Map<String, String>> _news = [];
  String _lastUpdated = '';
  int _newsPage = 1;
  static const int _newsPerPage = 10;

  static const _kBrown = Color(0xFF6B3E26);
  static const _kOrange = Color(0xFFFF5000);
  static const _kGreen = Color(0xFF10B981);

  String _formatTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  String _formatNewsDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.tryParse(raw);
      if (dt != null) {
        final local = dt.toLocal();
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        final m = months[local.month - 1];
        final h = local.hour.toString().padLeft(2, '0');
        final min = local.minute.toString().padLeft(2, '0');
        return '$m ${local.day}, $h:$min';
      }
    } catch (_) {}
    return raw
        .replaceAll(RegExp(r':\d{2}\.\d+.*'), '')
        .replaceAll(RegExp(r':\d{2}\s*(\+.*|Z)?$'), '')
        .replaceAll(RegExp(r'\s*\+0000$'), '')
        .replaceAll(RegExp(r'\s*GMT$'), '')
        .trim();
  }

  @override
  void initState() {
    super.initState();
    _lastUpdated = _formatTime();
    _loadForex();
    _loadNews();
  }

  Future<void> _loadForex() async {
    await _api.fetchDataWithCache('intelligence', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (!mounted) return;
      final snap = ForexSnapshot.fromIntelligence(data);
      if (snap != null) {
        setState(() {
          _forex = snap.rates;
          _forexIsSample = snap.isSample;
          _forexUpdated = snap.updatedLabel;
          _forexLoading = false;
        });
      } else if (!isCached) {
        if (mounted) setState(() => _forexLoading = false);
      }
    });
  }

  Future<void> _loadNews() async {
    setState(() {
      _newsLoading = true;
    });
    try {
      final res = await _api.getPublic('news/global');
      if (res is List) {
        final List<Map<String, String>> parsed = [];
        for (final item in res) {
          if (item is Map) {
            parsed.add({
              'title': item['title']?.toString() ?? '',
              'source': item['source']?.toString() ?? '',
              'date': item['pubDate']?.toString() ?? '',
              'description': item['description']?.toString() ?? '',
              'thumbnail': item['thumbnail']?.toString() ?? '',
              'sourceColor': item['sourceColor']?.toString() ?? '#3b82f6',
            });
          }
        }
        if (mounted) {
          setState(() {
            _news = parsed;
            _newsLoading = false;
            _lastUpdated = _formatTime();
          });
          return;
        }
      }
    } catch (e, st) {
      AppLogger.error('live_data_page', e, st);
    }
    if (mounted) {
      setState(() {
        _news = [];
        _newsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E130D) : Colors.white;
    final border = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final text = isDark ? const Color(0xFFFFF8F3) : const Color(0xFF2B211D);
    final muted = isDark ? const Color(0xFFC8ADA0) : const Color(0xFF6F625B);
    final surfaceRaised = isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);

    final totalPages = (_news.length / _newsPerPage).ceil().clamp(1, 999);
    final pageItems = _news
        .skip((_newsPage - 1) * _newsPerPage)
        .take(_newsPerPage)
        .toList();

    return AppLayout(
      title: 'Intelligence Hub',
      scrollable: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Live indicator header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const _BlinkingDot(color: _kGreen),
                        const SizedBox(width: 6),
                        const Text(
                          'LIVE INTELLIGENCE STREAM',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _kGreen,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Synced $_lastUpdated',
                      style: TextStyle(
                        fontSize: 12,
                        color: muted,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await _loadForex();
                      await _loadNews();
                    },
                    color: _kOrange,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Forex Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: border, width: 1.0),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.currency_exchange_rounded,
                                      color: _kBrown,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _forexIsSample
                                            ? 'Forex Rates (sample)'
                                            : 'Official Customs Forex Rates',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15.5,
                                          color: text,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    if (!_forexLoading && _forexIsSample)
                                      const _SampleBadge(),
                                  ],
                                ),
                                if (!_forexLoading &&
                                    (_forexIsSample || _forexUpdated.isNotEmpty)) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _forexIsSample
                                        ? ForexSnapshot.sampleNotice
                                        : _forexUpdated,
                                    style: TextStyle(fontSize: 12, color: muted),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                if (_forexLoading)
                                  GridView.count(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10,
                                    childAspectRatio: 2.4,
                                    children: List.generate(
                                      4,
                                      (i) => const ShimmerListTile(),
                                    ),
                                  )
                                else
                                  GridView.count(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10,
                                    childAspectRatio: 2.4,
                                    children: _forex.entries.map((e) {
                                      final symbols = {
                                        'USD': '\$',
                                        'EUR': '€',
                                        'GBP': '£',
                                        'CNY': '¥',
                                      };
                                      final symbol = symbols[e.key] ?? '';

                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: surfaceRaised,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: border,
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: cardBg,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: border, width: 1.0),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  symbol,
                                                  style: TextStyle(
                                                    color: text,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${e.key} / GHS',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: muted,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      e.value,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 16.5,
                                                        color: text,
                                                        letterSpacing: -0.3,
                                                        fontFeatures: const [
                                                          FontFeature.tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
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
                          const SizedBox(height: 20),

                          // News Section Header
                          Row(
                            children: [
                              const Icon(
                                Icons.directions_boat_rounded,
                                color: _kBrown,
                                size: 19,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Maritime & Customs Intelligence',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: text,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const Spacer(),
                              if (!_newsLoading)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: surfaceRaised,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: border, width: 1.0),
                                  ),
                                  child: Text(
                                    '${_news.length} articles',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: muted,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'gCaptain · Hellenic Shipping · Splash247 · FreightWaves · CUBAG Updates',
                            style: TextStyle(
                              fontSize: 12,
                              color: muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // News Feed Content
                          if (_newsLoading)
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 4,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  const ShimmerListTile(),
                            )
                          else ...[
                            ...pageItems.map((news) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: border, width: 1.0),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: surfaceRaised,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: border, width: 1.0),
                                          ),
                                          child: Text(
                                            (news['source'] ?? '').toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: _kBrown,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            _formatNewsDate(news['date']),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: muted,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      news['title'] ?? '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: text,
                                        height: 1.3,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    if ((news['description'] ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        news['description'] ?? '',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: muted,
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),

                            if (totalPages > 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        size: 13,
                                      ),
                                      onPressed: _newsPage > 1
                                          ? () => setState(() => _newsPage--)
                                          : null,
                                      color: text,
                                      disabledColor: muted.withValues(alpha: 0.4),
                                    ),
                                    const SizedBox(width: 6),
                                    ...List.generate(
                                      totalPages,
                                      (i) => i + 1,
                                    ).map((n) {
                                      final isSelected = _newsPage == n;
                                      return GestureDetector(
                                        onTap: () => setState(() => _newsPage = n),
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          width: 30,
                                          height: 30,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isSelected ? _kBrown : cardBg,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isSelected ? _kBrown : border,
                                              width: 1.0,
                                            ),
                                          ),
                                          child: Text(
                                            '$n',
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : text,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 13,
                                      ),
                                      onPressed: _newsPage < totalPages
                                          ? () => setState(() => _newsPage++)
                                          : null,
                                      color: text,
                                      disabledColor: muted.withValues(alpha: 0.4),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  final Color color;
  const _BlinkingDot({required this.color});

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}


/// Amber "SAMPLE" chip for placeholder data (BUG-10 / IOS-15).
class _SampleBadge extends StatelessWidget {
  const _SampleBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sample data, not official',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'SAMPLE',
          style: TextStyle(
            fontSize: 10,
            color: Color(0xFF92400E),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
