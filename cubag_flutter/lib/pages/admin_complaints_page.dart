import '../components/filter_tabs.dart';
import '../components/cubag_ui.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../utils/app_colors.dart';
import '../design/cubag_design.dart';

const _kBrown = Color(0xFF6B3E26);
const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kBlue = Color(0xFF3B82F6);
const _kPurple = Color(0xFF8B5CF6);
const _kRed = CubagColors.lapsed;
const _kSlate = CubagColors.muted;

class AdminComplaintsPage extends StatefulWidget {
  const AdminComplaintsPage({super.key});

  @override
  State<AdminComplaintsPage> createState() => _AdminComplaintsPageState();
}

class _AdminComplaintsPageState extends State<AdminComplaintsPage> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _complaints = [];
  bool _loading = true;
  bool _hasError = false;
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    _fetchComplaints();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchComplaints() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final res = await _api.get('/complaints');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = res.data;
        List<Map<String, dynamic>> items = [];
        if (data is Map && data['data'] is List) {
          items = (data['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } else if (data is List) {
          items = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        setState(() {
          _complaints = items;
          _loading = false;
          _hasError = false;
        });
      } else {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    } catch (e, st) {
      AppLogger.error('admin_complaints_fetch', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  String _normalizeStatus(String raw) {
    return raw.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ').trim();
  }

  int _countForStatus(String status) {
    if (status == 'all') return _complaints.length;
    final target = _normalizeStatus(status);
    return _complaints.where((c) {
      final current = _normalizeStatus(c['status']?.toString() ?? '');
      return current == target;
    }).length;
  }

  List<Map<String, dynamic>> get _displayedComplaints {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _complaints.where((c) {
      if (_selectedStatus != 'all') {
        final current = _normalizeStatus(c['status']?.toString() ?? '');
        final target = _normalizeStatus(_selectedStatus);
        if (target == 'resolved') {
          if (current != 'resolved' && current != 'closed') return false;
        } else if (current != target) {
          return false;
        }
      }
      if (query.isNotEmpty) {
        final id = (c['complaint_id']?.toString() ?? '').toLowerCase();
        final name = (c['name']?.toString() ?? '').toLowerCase();
        final subject = (c['subject']?.toString() ?? '').toLowerCase();
        final phone = (c['phone']?.toString() ?? '').toLowerCase();
        final port = (c['port']?.toString() ?? '').toLowerCase();
        final desc = (c['description']?.toString() ?? '').toLowerCase();
        final entity = (c['target_entity']?.toString() ?? '').toLowerCase();
        if (!id.contains(query) &&
            !name.contains(query) &&
            !subject.contains(query) &&
            !phone.contains(query) &&
            !port.contains(query) &&
            !desc.contains(query) &&
            !entity.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
      case 'closed':
        return _kGreen;
      case 'under review':
        return _kBlue;
      case 'investigating':
        return _kPurple;
      case 'received':
        return _kOrange;
      default:
        return _kSlate;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return _kRed;
      case 'high':
        return _kOrange;
      default:
        return _kSlate;
    }
  }

  void _openUpdateDialog(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final fieldBg = isDark ? CubagColors.ink : const Color(0xFFFAF6F0);
    final borderCol = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final textColor = isDark ? Colors.white : const Color(0xFF1F1612);
    final subTextColor = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

    String status = item['status']?.toString() ?? 'Received';
    String priority = item['priority']?.toString() ?? 'Normal';
    final notesCtrl = TextEditingController(text: item['resolution_notes']?.toString() ?? '');
    final assignedCtrl = TextEditingController(text: item['assigned_to']?.toString() ?? 'Secretariat Grievance Committee');
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          return AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: _kOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.gavel_rounded, color: _kOrange, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Update complaint', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                      Text(item['complaint_id']?.toString() ?? '', style: TextStyle(fontSize: 12, color: AppColors.accentOrangeText, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status selector
                    Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderCol)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ['Received', 'Under Review', 'Investigating', 'Resolved', 'Closed'].contains(status) ? status : 'Received',
                          isExpanded: true,
                          dropdownColor: dialogBg,
                          style: TextStyle(color: textColor, fontSize: 13),
                          items: const [
                            DropdownMenuItem(value: 'Received', child: Text('Received')),
                            DropdownMenuItem(value: 'Under Review', child: Text('Under review')),
                            DropdownMenuItem(value: 'Investigating', child: Text('Investigating')),
                            DropdownMenuItem(value: 'Resolved', child: Text('Resolved')),
                            DropdownMenuItem(value: 'Closed', child: Text('Closed')),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => status = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Priority
                    Text('Priority', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderCol)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ['Normal', 'High', 'Urgent'].contains(priority) ? priority : 'Normal',
                          isExpanded: true,
                          dropdownColor: dialogBg,
                          style: TextStyle(color: textColor, fontSize: 13),
                          items: const [
                            DropdownMenuItem(value: 'Normal', child: Text('Normal')),
                            DropdownMenuItem(value: 'High', child: Text('High')),
                            DropdownMenuItem(value: 'Urgent', child: Text('Urgent')),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => priority = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Assigned Handler
                    Text('Assigned to', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: assignedCtrl,
                      style: TextStyle(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: fieldBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderCol)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderCol)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange, width: 1.2)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Resolution Directives
                    Text('Resolution notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      style: TextStyle(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Findings, hearing dates or next steps',
                        hintStyle: TextStyle(fontSize: 12, color: subTextColor),
                        filled: true,
                        fillColor: fieldBg,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderCol)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderCol)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange, width: 1.2)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: TextStyle(color: subTextColor, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        setModalState(() => saving = true);
                        try {
                          final res = await _api.put(
                            '/complaints/${item['complaint_id']}/status',
                            data: {
                              'status': status,
                              'priority': priority,
                              'assigned_to': assignedCtrl.text.trim(),
                              'resolution_notes': notesCtrl.text.trim(),
                            },
                          );
                          if (!mounted) return;
                          if (res.statusCode == 200) {
                            if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                            _fetchComplaints();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: _kGreen,
                                  content: Text('Complaint updated.'),
                                ),
                              );
                            }
                          } else {
                            setModalState(() => saving = false);
                          }
                        } catch (e, st) {
                          AppLogger.error('admin_complaints_update', e, st);
                          setModalState(() => saving = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openViewDetailsDialog(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF22140E) : const Color(0xFFFBF8F3);
    final fieldBg = isDark ? CubagColors.ink : const Color(0xFFFAF6F0);
    final borderCol = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final textColor = isDark ? Colors.white : const Color(0xFF1F1612);
    final subTextColor = isDark ? const Color(0xFFB0A298) : const Color(0xFF6B5E55);

    final complaintId = item['complaint_id']?.toString() ?? '';
    final status = item['status']?.toString() ?? 'Received';
    final priority = item['priority']?.toString() ?? 'Normal';
    final targetEntity = item['target_entity']?.toString() ?? '';
    final description = item['description']?.toString() ?? item['details']?.toString() ?? 'No detailed description provided.';
    final category = item['category']?.toString() ?? 'Dispute';
    final port = item['port']?.toString() ?? 'Tema Port';
    final name = item['name']?.toString() ?? 'Complainant';
    final email = item['email']?.toString() ?? 'N/A';
    final phone = item['phone']?.toString() ?? 'N/A';
    final company = item['company']?.toString() ?? item['member_company']?.toString() ?? 'N/A';
    final assignedTo = item['assigned_to']?.toString() ?? 'Secretariat Grievance Committee';
    final resolutionNotes = item['resolution_notes']?.toString() ?? '';
    final createdAt = item['created_at']?.toString().split('T').first ?? '';

    final statusCol = _statusColor(status);
    final priorityCol = _priorityColor(priority);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _kOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.description_rounded, color: _kOrange, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Complaint', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: complaintId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Tracking ID $complaintId copied'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _kBrown.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(complaintId, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.accentOrangeText)),
                              const SizedBox(width: 3),
                              const Icon(Icons.copy_rounded, size: 10, color: _kOrange),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text('Filed $createdAt', style: TextStyle(fontSize: 11.5, color: subTextColor)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded, size: 18),
              color: subTextColor,
              onPressed: () => Navigator.pop(dialogCtx),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status Bar
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusCol.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusCol.withValues(alpha: 0.3)),
                      ),
                      child: Text(status.toUpperCase(), style: TextStyle(color: statusCol, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: priorityCol.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: priorityCol.withValues(alpha: 0.3)),
                      ),
                      child: Text('PRIORITY: ${priority.toUpperCase()}', style: TextStyle(color: priorityCol, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const Spacer(),
                    Text('$port • $category', style: TextStyle(fontSize: 11.5, color: subTextColor, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 14),

                // Complainant Details Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderCol)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('Complainant: $name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
                      const SizedBox(height: 4),
                      SelectableText('Contact: $phone | $email', style: TextStyle(fontSize: 12, color: subTextColor)),
                      if (company != 'N/A') ...[
                        const SizedBox(height: 2),
                        SelectableText('Company: $company', style: TextStyle(fontSize: 12, color: AppColors.accentOrangeText, fontWeight: FontWeight.w500)),
                      ],
                      if (targetEntity.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        SelectableText('Target Entity: $targetEntity', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _kPurple)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Subject & Description
                Text('Subject', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: subTextColor, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                SelectableText(item['subject']?.toString() ?? 'No Subject', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 8),

                Text('Details', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: subTextColor, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderCol)),
                  child: SelectableText(description, style: TextStyle(fontSize: 12.5, color: textColor, height: 1.4)),
                ),
                const SizedBox(height: 12),

                // Assigned & Resolution
                if (assignedTo.isNotEmpty) ...[
                  SelectableText('Assigned to: $assignedTo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subTextColor)),
                  const SizedBox(height: 6),
                ],
                if (resolutionNotes.isNotEmpty) ...[
                  Text('Resolution', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _kGreen, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _kGreen.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kGreen.withValues(alpha: 0.25))),
                    child: SelectableText(resolutionNotes, style: TextStyle(fontSize: 12.5, color: textColor, height: 1.35)),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Close', style: TextStyle(color: subTextColor)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _openUpdateDialog(item);
            },
            icon: const Icon(Icons.edit_note_rounded, size: 16),
            label: Text('Update', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final complaints = _displayedComplaints;
    final resolved = _countForStatus('Resolved') + _countForStatus('Closed');
    AdminFigure fig(String label, String key, int n, {Color? color}) => AdminFigure(
          label,
          '$n',
          color: n > 0 ? color : null,
          selected: _selectedStatus.toLowerCase() == key.toLowerCase(),
          onTap: () => setState(() => _selectedStatus = key),
        );

    return AppLayout(
      title: 'Complaints',
      scrollable: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminHeader(
                title: 'Complaints',
                subtitle: 'Complaints from members and the public. Open one to read it, then update its status as you work on it.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: _fetchComplaints,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              AdminFigureStrip(figures: [
                fig('All', 'all', _complaints.length),
                fig('New', 'Received', _countForStatus('Received'), color: CubagColors.due),
                fig('Under review', 'Under Review', _countForStatus('Under Review'), color: CubagColors.due),
                fig('Investigating', 'Investigating', _countForStatus('Investigating'), color: CubagColors.due),
                fig('Resolved', 'Resolved', resolved, color: CubagColors.valid),
              ]),
              const SizedBox(height: CubagSpace.md),
              AdminSearchField(
                hint: 'Search name, subject, phone or tracking ID',
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: CubagSpace.md),
              if (_loading)
                Column(
                  children: List.generate(
                    4,
                    (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile()),
                  ),
                )
              else if (_hasError)
                EmptyMessage(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load complaints',
                  message: 'Check the connection and try again.',
                  action: OutlinedButton(onPressed: _fetchComplaints, child: const Text('Try again')),
                )
              else if (complaints.isEmpty)
                EmptyMessage(
                  icon: Icons.gavel_rounded,
                  title: _complaints.isEmpty ? 'No complaints yet' : 'No complaints match',
                  message: _complaints.isEmpty
                      ? 'Complaints sent from the app or the public form appear here.'
                      : 'Try another filter, or clear the search.',
                )
              else ...[
                AdminRowGroup(
                  dividerIndent: 68,
                  children: [for (final item in complaints) _complaintRow(item)],
                ),
                const SizedBox(height: CubagSpace.sm),
                Text(
                  'Showing ${complaints.length} of ${_complaints.length}',
                  style: CubagType.caption,
                ),
              ],
              const SizedBox(height: CubagSpace.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _complaintRow(Map<String, dynamic> item) {
    final id = item['complaint_id']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Complainant';
    final subject = item['subject']?.toString() ?? 'No subject';
    final port = item['port']?.toString() ?? '';
    final category = item['category']?.toString() ?? '';
    final status = item['status']?.toString() ?? 'Received';
    final priority = item['priority']?.toString() ?? 'Normal';
    final norm = _normalizeStatus(status);
    final kind = switch (norm) {
      'resolved' || 'closed' => StatusKind.good,
      'rejected' || 'dismissed' => StatusKind.bad,
      _ => StatusKind.pending,
    };
    final label = norm == 'received' ? 'New' : (status.isEmpty ? 'New' : status[0].toUpperCase() + status.substring(1).toLowerCase());
    final urgent = const {'high', 'urgent', 'critical'}.contains(priority.toLowerCase());

    return AdminListRow(
      leading: AdminRowMark(
        icon: Icons.gavel_rounded,
        color: urgent ? CubagColors.lapsed : CubagColors.cocoa,
        background: urgent ? CubagColors.lapsedTint : CubagColors.sand,
      ),
      title: subject,
      subtitle: [name, if (port.isNotEmpty) port, if (category.isNotEmpty) category].join(' · '),
      meta: [if (id.isNotEmpty) id, if (urgent) '${priority[0].toUpperCase()}${priority.substring(1).toLowerCase()} priority'].join(' · '),
      status: StatusChip(label, kind: kind),
      onTap: () => _openViewDetailsDialog(item),
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert_rounded, color: CubagColors.muted),
        onSelected: (v) {
          if (v == 'update') _openUpdateDialog(item);
          if (v == 'open') _openViewDetailsDialog(item);
          if (v == 'copy') {
            Clipboard.setData(ClipboardData(text: id));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Tracking ID $id copied'), behavior: SnackBarBehavior.floating),
            );
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'open', child: Text('Open')),
          const PopupMenuItem(value: 'update', child: Text('Update status')),
          if (id.isNotEmpty) const PopupMenuItem(value: 'copy', child: Text('Copy tracking ID')),
        ],
      ),
    );
  }
}
