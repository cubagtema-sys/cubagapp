import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

/// Simplified search for regular (non-admin) members.
/// Searches the public directory, announcements, and schedules.
class MemberSearchDelegate extends SearchDelegate<String> {
  @override
  String get searchFieldLabel => 'Search directory, announcements...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF64748b)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Color(0xFF94a3b8), fontSize: 16),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear, size: 20),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, size: 20),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildBody(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildBody(context);

  Widget _buildBody(BuildContext context) {
    if (query.length < 2) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 48, color: Color(0xFFcbd5e1)),
            SizedBox(height: 12),
            Text(
              'Search the broker directory & announcements',
              style: TextStyle(color: Color(0xFF94a3b8), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return _DebouncedMemberSearch(
      query: query,
      onNavigate: (type) {
        close(context, '');
        switch (type) {
          case 'directory':
            context.go('/networking');
            break;
          case 'announcement':
            context.go('/announcements');
            break;
          case 'schedule':
            context.go('/vanning-schedules');
            break;
        }
      },
    );
  }
}

class _DebouncedMemberSearch extends StatefulWidget {
  final String query;
  final Function(String type) onNavigate;

  const _DebouncedMemberSearch({required this.query, required this.onNavigate});

  @override
  State<_DebouncedMemberSearch> createState() => _DebouncedMemberSearchState();
}

class _DebouncedMemberSearchState extends State<_DebouncedMemberSearch> {
  Timer? _debounce;
  List<_SearchResult> _results = [];
  bool _loading = false;
  String _lastSearched = '';

  @override
  void initState() {
    super.initState();
    _scheduleSearch(widget.query);
  }

  @override
  void didUpdateWidget(covariant _DebouncedMemberSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _scheduleSearch(widget.query);
    }
  }

  void _scheduleSearch(String q) {
    _debounce?.cancel();
    if (q == _lastSearched) return;
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _doSearch(q));
  }

  Future<void> _doSearch(String q) async {
    final pattern = q.toLowerCase();
    final results = <_SearchResult>[];

    try {
      // Search public directory (Good Standing members only)
      final items = await ApiService().getPublic(
        'members/public/members?search=${Uri.encodeComponent(pattern)}',
      );
      if (items is List) {
        for (final m in items) {
          final name = (m['name'] ?? '').toString().toLowerCase();
          final type = (m['type'] ?? '').toString().toLowerCase();
          final loc = (m['location'] ?? '').toString().toLowerCase();
          if (name.contains(pattern) ||
              type.contains(pattern) ||
              loc.contains(pattern)) {
            results.add(
              _SearchResult(
                title: m['name']?.toString() ?? '',
                subtitle: '${m['type']} • ${m['location']}',
                type: 'directory',
                icon: Icons.business_outlined,
                color: const Color(0xFF3b82f6),
              ),
            );
          }
        }
      }
    } catch (e, st) {
      AppLogger.error('member_search_delegate', e, st);
    }

    try {
      // Search announcements
      final annRes = await ApiService().get('/announcements/');
      if (annRes.statusCode == 200) {
        final items = ApiService.ensureList(annRes.data);
        for (final a in items) {
          final title = (a['title'] ?? '').toString().toLowerCase();
          final body = (a['body'] ?? '').toString().toLowerCase();
          if (title.contains(pattern) || body.contains(pattern)) {
            results.add(
              _SearchResult(
                title: a['title']?.toString() ?? '',
                subtitle: a['category']?.toString() ?? 'General',
                type: 'announcement',
                icon: Icons.campaign_outlined,
                color: const Color(0xFFFF5000),
              ),
            );
          }
        }
      }
    } catch (e, st) {
      AppLogger.error('member_search_delegate', e, st);
    }

    try {
      // Search schedules
      final schRes = await ApiService().get('/schedules/');
      if (schRes.statusCode == 200) {
        final items = ApiService.ensureList(schRes.data);
        for (final s in items) {
          final vessel = (s['vessel'] ?? '').toString().toLowerCase();
          final cargo = (s['cargo'] ?? '').toString().toLowerCase();
          final container = (s['container'] ?? '').toString().toLowerCase();
          if (vessel.contains(pattern) ||
              cargo.contains(pattern) ||
              container.contains(pattern)) {
            results.add(
              _SearchResult(
                title:
                    s['vessel']?.toString() ?? s['container']?.toString() ?? '',
                subtitle: '${s['cargo'] ?? ''} • ${s['port'] ?? ''}',
                type: 'schedule',
                icon: Icons.local_shipping_outlined,
                color: const Color(0xFF10b981),
              ),
            );
          }
        }
      }
    } catch (e, st) {
      AppLogger.error('member_search_delegate', e, st);
    }

    if (mounted) {
      setState(() {
        _results = results;
        _loading = false;
        _lastSearched = q;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF5000)),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Color(0xFFcbd5e1)),
            const SizedBox(height: 12),
            Text(
              'No results for "${widget.query}"',
              style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final r = _results[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 2,
          ),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: r.color.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(r.icon, color: r.color, size: 18),
          ),
          title: Text(
            r.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            r.subtitle,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748b)),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: r.color.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              r.type == 'directory'
                  ? 'BROKER'
                  : r.type == 'announcement'
                  ? 'ALERT'
                  : 'SCHEDULE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: r.color,
              ),
            ),
          ),
          onTap: () => widget.onNavigate(r.type),
        );
      },
    );
  }
}

class _SearchResult {
  final String title;
  final String subtitle;
  final String type;
  final IconData icon;
  final Color color;

  _SearchResult({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.icon,
    required this.color,
  });
}
