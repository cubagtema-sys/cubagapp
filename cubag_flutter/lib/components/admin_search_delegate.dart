import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';

/// Admin search with debounce (Feature 6) — waits 300ms before firing API.
class AdminSearchDelegate extends SearchDelegate<String> {
  Timer? _debounce;

  @override
  String get searchFieldLabel => 'Search members, payments, tickets...';

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
          onPressed: () {
            query = '';
            _debounce?.cancel();
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back, size: 20),
      onPressed: () {
        _debounce?.cancel();
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    if (query.length < 2) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 48, color: Color(0xFFcbd5e1)),
            SizedBox(height: 12),
            Text(
              'Type at least 2 characters to search',
              style: TextStyle(color: Color(0xFF94a3b8), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return _DebouncedSearchBody(
      query: query,
      onNavigate: (result) {
        close(context, '');
        _navigateToResult(context, result);
      },
    );
  }

  void _navigateToResult(BuildContext context, Map<String, dynamic> result) {
    final type = result['result_type']?.toString() ?? 'member';
    switch (type) {
      case 'payment':
        context.go('/admin/payments');
        break;
      case 'ticket':
        context.go('/admin/tickets');
        break;
      default:
        context.go('/admin/members');
    }
  }
}

/// Stateful widget that debounces the API call by 300ms.
class _DebouncedSearchBody extends StatefulWidget {
  final String query;
  final Function(Map<String, dynamic>) onNavigate;

  const _DebouncedSearchBody({required this.query, required this.onNavigate});

  @override
  State<_DebouncedSearchBody> createState() => _DebouncedSearchBodyState();
}

class _DebouncedSearchBodyState extends State<_DebouncedSearchBody> {
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String _lastSearched = '';

  @override
  void initState() {
    super.initState();
    _scheduleSearch(widget.query);
  }

  @override
  void didUpdateWidget(covariant _DebouncedSearchBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _scheduleSearch(widget.query);
    }
  }

  void _scheduleSearch(String q) {
    _debounce?.cancel();
    if (q == _lastSearched) return;

    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _doSearch(q);
    });
  }

  Future<void> _doSearch(String q) async {
    try {
      final res = await ApiService().get('/admin/search?q=$q');
      if (res.statusCode == 200 && mounted) {
        final data = res.data as Map<String, dynamic>;
        setState(() {
          _results = List<Map<String, dynamic>>.from(data['results'] ?? []);
          _loading = false;
          _lastSearched = q;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
        final type = r['result_type']?.toString() ?? 'member';
        final icon = _iconForType(type);
        final color = _colorForType(type);
        final label = _labelForType(type);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 2,
          ),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          title: Text(
            r['name']?.toString() ?? 'Unknown',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            r['email']?.toString() ?? '',
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748b)),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          onTap: () => widget.onNavigate(r),
        );
      },
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'payment':
        return Icons.payments_outlined;
      case 'ticket':
        return Icons.support_agent_outlined;
      default:
        return Icons.person_outline;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'payment':
        return const Color(0xFF10b981);
      case 'ticket':
        return const Color(0xFFef4444);
      default:
        return const Color(0xFF3b82f6);
    }
  }

  String _labelForType(String type) {
    switch (type) {
      case 'payment':
        return 'Payment';
      case 'ticket':
        return 'Ticket';
      default:
        return 'Member';
    }
  }
}
