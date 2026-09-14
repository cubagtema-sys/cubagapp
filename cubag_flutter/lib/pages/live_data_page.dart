import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

class LiveDataPage extends StatefulWidget {
  const LiveDataPage({super.key});

  @override
  State<LiveDataPage> createState() => _LiveDataPageState();
}

class _LiveDataPageState extends State<LiveDataPage> {
  final _api = ApiService();
  Map<String, String> _forex = {
    'USD': '15.45',
    'EUR': '16.80',
    'GBP': '19.50',
    'CNY': '2.15',
  };
  bool _forexLoading = false;
  bool _newsLoading = true;
  List<Map<String, String>> _news = [];
  String _lastUpdated = '';
  int _newsPage = 1;
  static const int _newsPerPage = 10;

  String _formatTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
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
      if (data != null &&
          data is Map &&
          data['forex'] != null &&
          data['forex'] is Map) {
        final forexMap = data['forex'] as Map;
        setState(() {
          _forex = {
            'USD': forexMap['USD']?.toString() ?? '15.45',
            'EUR': forexMap['EUR']?.toString() ?? '16.80',
            'GBP': forexMap['GBP']?.toString() ?? '19.50',
            'CNY': forexMap['CNY']?.toString() ?? '2.15',
          };
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
    final primary = Theme.of(context).primaryColor;
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
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Live indicator header
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const _BlinkingDot(color: Color(0xFF10b981)),
                    const SizedBox(width: 6),
                    Text(
                      'LIVE INTELLIGENCE',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: const Color(0xFF10b981),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Synced at $_lastUpdated',
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        color: const Color(0xFF94a3b8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await _loadForex();
                      await _loadNews();
                    },
                    color: primary,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Forex Card
                          Card(
                            color: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: const Color(0xFFcbd5e1).withAlpha(120),
                                width: 1.5,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.currency_exchange_rounded,
                                        color: primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Official Forex Rates',
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 17,
                                          color: const Color(0xFF281710),
                                        ),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          'CUBAG Admin Rate',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (_forexLoading)
                                    GridView.count(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 2.3,
                                      children: List.generate(
                                        4,
                                        (i) => const ShimmerListTile(),
                                      ),
                                    )
                                  else
                                    GridView.count(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 2.3,
                                      children: _forex.entries.map((e) {
                                        final symbols = {
                                          'USD': '\$',
                                          'EUR': '€',
                                          'GBP': '£',
                                          'CNY': '¥',
                                        };
                                        final symbol = symbols[e.key] ?? '';
                                        final colors = {
                                          'USD': const Color(0xFF3b82f6),
                                          'EUR': const Color(0xFF10b981),
                                          'GBP': const Color(0xFF8b5cf6),
                                          'CNY': const Color(0xFFf59e0b),
                                        };
                                        final symbolBg =
                                            colors[e.key]?.withAlpha(15) ??
                                            const Color(0xFFf1f5f9);
                                        final symbolColor =
                                            colors[e.key] ??
                                            const Color(0xFF64748b);

                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                            horizontal: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFf8fafc),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFFcbd5e1,
                                              ).withAlpha(100),
                                              width: 1.2,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: symbolBg,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    symbol,
                                                    style: GoogleFonts.outfit(
                                                      color: symbolColor,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w900,
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
                                                      style: GoogleFonts.outfit(
                                                        fontSize: 12,
                                                        color: const Color(
                                                          0xFF64748b,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                        e.value,
                                                        style:
                                                            GoogleFonts.outfit(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              fontSize: 17.5,
                                                              color:
                                                                  const Color(
                                                                    0xFF281710,
                                                                  ),
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
                          ),
                          const SizedBox(height: 24),

                          // News Section Header
                          Row(
                            children: [
                              Icon(
                                Icons.directions_boat_rounded,
                                color: const Color(0xFF3b82f6),
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Maritime & Customs Intelligence',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF281710),
                                ),
                              ),
                              const Spacer(),
                              if (!_newsLoading)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFf1f5f9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_news.length} articles',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12.5,
                                      color: const Color(0xFF64748b),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'gCaptain · Hellenic Shipping · Splash247 · FreightWaves · CUBAG Updates',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: const Color(0xFF94a3b8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // News Feed Content
                          if (_newsLoading)
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 4,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) =>
                                  const ShimmerListTile(),
                            )
                          else ...[
                            ...pageItems.map((news) {
                              Color? srcColor;
                              final hexStr = news['sourceColor'];
                              if (hexStr != null) {
                                try {
                                  final cleanHex = hexStr.replaceAll('#', '');
                                  srcColor = Color(
                                    int.parse('FF$cleanHex', radix: 16),
                                  );
                                } catch (e, st) {
                                  AppLogger.error('live_data_page', e, st);
                                }
                              }
                              final displayColor = srcColor ?? primary;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border(
                                    left: BorderSide(
                                      color: displayColor,
                                      width: 4.5,
                                    ),
                                    top: BorderSide(
                                      color: const Color(
                                        0xFFcbd5e1,
                                      ).withAlpha(120),
                                      width: 1.5,
                                    ),
                                    right: BorderSide(
                                      color: const Color(
                                        0xFFcbd5e1,
                                      ).withAlpha(120),
                                      width: 1.5,
                                    ),
                                    bottom: BorderSide(
                                      color: const Color(
                                        0xFFcbd5e1,
                                      ).withAlpha(120),
                                      width: 1.5,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(4),
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: displayColor.withAlpha(20),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            (news['source'] ?? '')
                                                .toUpperCase(),
                                            style: GoogleFonts.outfit(
                                              fontSize: 11.5,
                                              color: displayColor,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          news['date'] ?? '',
                                          style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            color: const Color(0xFF94a3b8),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      news['title'] ?? '',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16.5,
                                        color: const Color(0xFF281710),
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      news['description'] ?? '',
                                      style: GoogleFonts.outfit(
                                        fontSize: 14.5,
                                        color: const Color(0xFF64748b),
                                        height: 1.4,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              );
                            }),

                            if (totalPages > 1)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        size: 14,
                                      ),
                                      onPressed: _newsPage > 1
                                          ? () => setState(() {
                                              _newsPage--;
                                            })
                                          : null,
                                      color: const Color(0xFF64748b),
                                      disabledColor: const Color(0xFFcbd5e1),
                                    ),
                                    const SizedBox(width: 8),
                                    ...List.generate(
                                      totalPages,
                                      (i) => i + 1,
                                    ).map((n) {
                                      final isSelected = _newsPage == n;
                                      return GestureDetector(
                                        onTap: () =>
                                            setState(() => _newsPage = n),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          width: 32,
                                          height: 32,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? primary
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? primary
                                                  : const Color(0xFFcbd5e1),
                                              width: 1.5,
                                            ),
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: primary.withAlpha(
                                                        40,
                                                      ),
                                                      blurRadius: 6,
                                                      offset: const Offset(
                                                        0,
                                                        2,
                                                      ),
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: Text(
                                            '$n',
                                            style: GoogleFonts.outfit(
                                              color: isSelected
                                                  ? Colors.white
                                                  : const Color(0xFF64748b),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14.5,
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 14,
                                      ),
                                      onPressed: _newsPage < totalPages
                                          ? () => setState(() => _newsPage++)
                                          : null,
                                      color: const Color(0xFF64748b),
                                      disabledColor: const Color(0xFFcbd5e1),
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
