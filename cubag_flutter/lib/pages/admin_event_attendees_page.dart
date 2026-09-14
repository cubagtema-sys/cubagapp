import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../components/app_layout.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

class AdminEventAttendeesPage extends StatefulWidget {
  final int eventId;
  final String title;

  const AdminEventAttendeesPage({
    super.key,
    required this.eventId,
    required this.title,
  });

  @override
  State<AdminEventAttendeesPage> createState() =>
      _AdminEventAttendeesPageState();
}

class _AdminEventAttendeesPageState extends State<AdminEventAttendeesPage> {
  bool _loading = true;
  List<dynamic> _allMembers = [];
  String _filter = 'all'; // 'all', 'attended', 'absent'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await ApiService().get('/events/${widget.eventId}/attendees');
      if (mounted && res.statusCode == 200) {
        setState(() {
          _allMembers = res.data['attendees'] ?? [];
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load attendees: ${res.data}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        try {
          final dynamic dioErr = e;
          if (dioErr.response != null && dioErr.response.data != null) {
            msg =
                dioErr.response.data['message'] ??
                dioErr.response.data.toString();
          }
        } catch (e, st) {
          AppLogger.error('admin_event_attendees_page', e, st);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading attendees: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
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
    final inputBg = isDark
        ? const Color(0xFF1A0F0A).withValues(alpha: 0.4)
        : const Color(0xFFf8fafc);
    final primary = Theme.of(context).primaryColor;

    List<dynamic> filtered = _allMembers.where((m) {
      final attended = m['checked_in_at'] != null;
      if (_filter == 'attended' && !attended) return false;
      if (_filter == 'absent' && attended) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = (m['name'] ?? '').toLowerCase();
        final company = (m['company'] ?? '').toLowerCase();
        if (!name.contains(q) && !company.contains(q)) return false;
      }
      return true;
    }).toList();

    int attendedCount = _allMembers
        .where((m) => m['checked_in_at'] != null)
        .length;
    int absentCount = _allMembers.length - attendedCount;

    return AppLayout(
      title: 'Attendees: ${widget.title}',
      scrollable: false,
      child: Column(
        children: [
          // Filter Tabs
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                _buildFilterChip(
                  'All',
                  'all',
                  _allMembers.length,
                  primary,
                  isDark,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Checked In',
                  'attended',
                  attendedCount,
                  const Color(0xFF10b981),
                  isDark,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Absent',
                  'absent',
                  absentCount,
                  const Color(0xFFef4444),
                  isDark,
                ),
              ],
            ),
          ),

          // Search Bar
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: GoogleFonts.outfit(color: textColor, fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Search by name or company...',
                hintStyle: GoogleFonts.outfit(
                  color: subTextColor,
                  fontSize: 18,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: subTextColor,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                filled: true,
                fillColor: inputBg,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: primary, width: 2),
                ),
              ),
            ),
          ),

          // List
          Expanded(
            child: _loading
                ? ListView.builder(
                    itemCount: 5,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: ShimmerListTile(),
                    ),
                  )
                : filtered.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'No members found.'
                          : 'No matches for "$_searchQuery".',
                      style: GoogleFonts.outfit(
                        color: subTextColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final a = filtered[i];
                      final bool isAttended = a['checked_in_at'] != null;
                      final nameStr = a['name']?.toString() ?? '';
                      final initial = nameStr.trim().isNotEmpty
                          ? nameStr.trim()[0].toUpperCase()
                          : '?';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.1 : 0.02,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: isAttended
                                ? const Color(
                                    0xFF10b981,
                                  ).withValues(alpha: 0.15)
                                : subTextColor.withValues(alpha: 0.15),
                            child: Text(
                              initial,
                              style: GoogleFonts.outfit(
                                color: isAttended
                                    ? const Color(0xFF10b981)
                                    : subTextColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            nameStr,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 19,
                              color: textColor,
                            ),
                          ),
                          subtitle: Text(
                            '${a['email'] ?? ''}\n${a['company'] ?? ''}',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              height: 1.5,
                              color: subTextColor,
                            ),
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (isAttended) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF10b981,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF10b981,
                                      ).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFF10b981),
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Checked In',
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFF10b981),
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: subTextColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: subTextColor.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.cancel_rounded,
                                        color: subTextColor,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Absent',
                                        style: GoogleFonts.outfit(
                                          color: subTextColor,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String value,
    int count,
    Color color,
    bool isDark,
  ) {
    final isSelected = _filter == value;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFe2e8f0);
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _filter = value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.5) : borderColor,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                count.toString(),
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: isSelected
                      ? color
                      : (isDark ? Colors.white : Colors.black),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? color
                      : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
