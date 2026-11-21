import 'package:flutter/material.dart';
import '../components/admin_list.dart';
import '../components/app_layout.dart';
import '../components/cubag_ui.dart';
import '../components/filter_tabs.dart';
import '../components/shimmer_loader.dart';
import '../design/cubag_design.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import 'admin_qr_scanner_page.dart';

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
  List<Map<String, dynamic>> _allMembers = [];
  String _filter = 'all'; // 'all', 'attended', 'absent'
  String _searchQuery = '';
  final Set<int> _processingMemberIds = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await ApiService().get('/events/${widget.eventId}/attendees');
      if (mounted && res.statusCode == 200) {
        final list = (res.data['attendees'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _allMembers = list;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load attendees: ${res.data}'),
            backgroundColor: CubagColors.lapsed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        try {
          final dynamic dioErr = e;
          if (dioErr.response != null && dioErr.response.data != null) {
            msg = dioErr.response.data['message'] ?? dioErr.response.data.toString();
          }
        } catch (e, st) {
          AppLogger.error('admin_event_attendees_page', e, st);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading attendees: $msg'),
            backgroundColor: CubagColors.lapsed,
          ),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _checkInMember(Map<String, dynamic> member) async {
    final memberId = member['id'] as int?;
    if (memberId == null) return;
    if (_processingMemberIds.contains(memberId)) return;

    setState(() => _processingMemberIds.add(memberId));
    try {
      final res = await ApiService().post(
        '/events/${widget.eventId}/check-in',
        data: {'member_id': memberId},
      );
      if (res.statusCode == 200) {
        final nowIso = DateTime.now().toIso8601String();
        setState(() {
          member['checked_in_at'] = nowIso;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ ${member['name'] ?? 'Member'} checked in successfully!'),
              backgroundColor: CubagColors.valid,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        final msg = res.data is Map ? (res.data['message'] ?? 'Check-in failed') : 'Check-in failed';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$msg'),
              backgroundColor: CubagColors.lapsed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        try {
          final dynamic dioErr = e;
          if (dioErr.response != null && dioErr.response.data != null) {
            msg = dioErr.response.data['message'] ?? dioErr.response.data.toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $msg'),
            backgroundColor: CubagColors.lapsed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingMemberIds.remove(memberId));
      }
    }
  }

  Future<void> _uncheckInMember(Map<String, dynamic> member) async {
    final memberId = member['id'] as int?;
    if (memberId == null) return;
    if (_processingMemberIds.contains(memberId)) return;

    setState(() => _processingMemberIds.add(memberId));
    try {
      final res = await ApiService().post(
        '/events/${widget.eventId}/uncheck-in',
        data: {'member_id': memberId},
      );
      if (res.statusCode == 200) {
        setState(() {
          member['checked_in_at'] = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Check-in removed for ${member['name'] ?? 'Member'}'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        final msg = res.data is Map ? (res.data['message'] ?? 'Failed to remove check-in') : 'Failed to remove check-in';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$msg'),
              backgroundColor: CubagColors.lapsed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: CubagColors.lapsed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingMemberIds.remove(memberId));
      }
    }
  }

  String _formatCheckInTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $ampm';
    } catch (_) {
      return '';
    }
  }

  void _openScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminQrScannerPage(
          onScan: (scannedVal) {
            final id = int.tryParse(scannedVal);
            final target = _allMembers.firstWhere(
              (m) =>
                  m['id'] == id ||
                  (m['membership_number'] != null &&
                      m['membership_number'].toString().toLowerCase() ==
                          scannedVal.toLowerCase()) ||
                  (m['email'] != null &&
                      m['email'].toString().toLowerCase() ==
                          scannedVal.toLowerCase()),
              orElse: () => <String, dynamic>{},
            );
            if (target.isNotEmpty) {
              _checkInMember(target);
            } else if (id != null) {
              _checkInMember({'id': id, 'name': 'Member #$id'});
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Member "$scannedVal" not found in attendee list'),
                  backgroundColor: CubagColors.lapsed,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allMembers.where((m) {
      final attended = m['checked_in_at'] != null;
      if (_filter == 'attended' && !attended) return false;
      if (_filter == 'absent' && attended) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = (m['name'] ?? '').toString().toLowerCase();
        final company = (m['company'] ?? '').toString().toLowerCase();
        final email = (m['email'] ?? '').toString().toLowerCase();
        final phone = (m['phone'] ?? '').toString().toLowerCase();
        final memNo = (m['membership_number'] ?? '').toString().toLowerCase();
        if (!name.contains(q) &&
            !company.contains(q) &&
            !email.contains(q) &&
            !phone.contains(q) &&
            !memNo.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
    final attendedCount = _allMembers.where((m) => m['checked_in_at'] != null).length;
    final absentCount = _allMembers.length - attendedCount;
    AdminFigure fig(String label, String key, int n, {Color? color}) => AdminFigure(
          label,
          '$n',
          color: n > 0 ? color : null,
          selected: _filter == key,
          onTap: () => setState(() => _filter = key),
        );

    return AppLayout(
      title: 'Attendees',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: CubagType.title),
                        const SizedBox(height: CubagSpace.xxs),
                        Text(
                          'Members who signed up, and who was checked in at the door.',
                          style: CubagType.small,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CubagSpace.sm),
                  FilledButton.icon(
                    onPressed: _openScanner,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text(
                      'Scan QR',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: CubagColors.action,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CubagSpace.md),
              AdminFigureStrip(figures: [
                fig('Signed up', 'all', _allMembers.length),
                fig('Checked in', 'attended', attendedCount, color: CubagColors.valid),
                fig('Not checked in', 'absent', absentCount),
              ]),
              const SizedBox(height: CubagSpace.md),
              AdminSearchField(
                hint: 'Search name, company, email or phone',
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                Column(
                  children: List.generate(
                    4,
                    (i) => const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: ShimmerListTile(),
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                EmptyMessage(
                  icon: Icons.groups_outlined,
                  title: _searchQuery.isNotEmpty
                      ? 'No one matches'
                      : (_allMembers.isEmpty
                          ? 'No one has signed up yet'
                          : 'No one in this list'),
                  message: _searchQuery.isNotEmpty
                      ? 'Try another name, or clear the search.'
                      : null,
                )
              else
                AdminRowGroup(
                  dividerIndent: 68,
                  children: [
                    for (final a in filtered) ...[
                      Builder(
                        builder: (ctx) {
                          final isCheckedIn = a['checked_in_at'] != null;
                          final checkInTime = _formatCheckInTime(a['checked_in_at']?.toString());
                          final isProcessing = _processingMemberIds.contains(a['id']);

                          return AdminListRow(
                            leading: AdminRowMark(
                              initials: adminInitials(a['name']?.toString() ?? ''),
                              color: isCheckedIn ? CubagColors.valid : CubagColors.cocoa,
                              background: isCheckedIn ? CubagColors.validTint : CubagColors.sand,
                            ),
                            title: a['name']?.toString() ?? 'Member',
                            subtitle: [
                              if ((a['company'] ?? '').toString().isNotEmpty)
                                a['company'].toString(),
                              if ((a['email'] ?? '').toString().isNotEmpty)
                                a['email'].toString(),
                              if (checkInTime.isNotEmpty)
                                'Checked in at $checkInTime',
                            ].join(' · '),
                            status: isCheckedIn
                                ? const StatusChip('Checked in', kind: StatusKind.good)
                                : const StatusChip('Not checked in'),
                            trailing: isCheckedIn
                                ? PopupMenuButton<String>(
                                    tooltip: 'Attendance actions',
                                    icon: const Icon(
                                      Icons.more_vert_rounded,
                                      color: CubagColors.muted,
                                      size: 20,
                                    ),
                                    onSelected: (v) {
                                      if (v == 'undo') _uncheckInMember(a);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'undo',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.undo_rounded,
                                              size: 16,
                                              color: CubagColors.lapsed,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Remove check-in',
                                              style: TextStyle(
                                                color: CubagColors.lapsed,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : SizedBox(
                                    height: 34,
                                    child: ElevatedButton.icon(
                                      onPressed: isProcessing
                                          ? null
                                          : () => _checkInMember(a),
                                      icon: isProcessing
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.check_circle_outline_rounded,
                                              size: 16,
                                            ),
                                      label: const Text(
                                        'Check in',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: CubagColors.action,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}
