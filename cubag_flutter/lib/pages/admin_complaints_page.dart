import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

const _kBrown = Color(0xFF6B3E26);
const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kBlue = Color(0xFF3B82F6);
const _kPurple = Color(0xFF8B5CF6);
const _kRed = Color(0xFFEF4444);
const _kSlate = Color(0xFF64748B);

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
    final dialogBg = isDark ? const Color(0xFF281710) : Colors.white;
    final fieldBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final borderCol = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

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
                      Text('Update Grievance Case', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                      Text(item['complaint_id']?.toString() ?? '', style: GoogleFonts.outfit(fontSize: 12, color: _kOrange, fontWeight: FontWeight.bold)),
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
                    Text('Status', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderCol)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ['Received', 'Under Review', 'Investigating', 'Resolved', 'Closed'].contains(status) ? status : 'Received',
                          isExpanded: true,
                          dropdownColor: dialogBg,
                          style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                          items: const [
                            DropdownMenuItem(value: 'Received', child: Text('Received (Logged into Registry)')),
                            DropdownMenuItem(value: 'Under Review', child: Text('Under Review (Assessment)')),
                            DropdownMenuItem(value: 'Investigating', child: Text('Investigating (Port Verification)')),
                            DropdownMenuItem(value: 'Resolved', child: Text('Resolved (Resolution Notice Issued)')),
                            DropdownMenuItem(value: 'Closed', child: Text('Closed (Finalized)')),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => status = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Priority
                    Text('Priority Level', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderCol)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ['Normal', 'High', 'Urgent'].contains(priority) ? priority : 'Normal',
                          isExpanded: true,
                          dropdownColor: dialogBg,
                          style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                          items: const [
                            DropdownMenuItem(value: 'Normal', child: Text('Normal Priority')),
                            DropdownMenuItem(value: 'High', child: Text('High Priority')),
                            DropdownMenuItem(value: 'Urgent', child: Text('Urgent Disciplinary Priority')),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => priority = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Assigned Handler
                    Text('Assigned Committee / Officer', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: assignedCtrl,
                      style: GoogleFonts.outfit(fontSize: 13, color: textColor),
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
                    Text('Official Resolution Notes & Directives', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: textColor)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 3,
                      style: GoogleFonts.outfit(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Enter formal Secretariat findings, hearing dates, or corrective directives...',
                        hintStyle: GoogleFonts.outfit(fontSize: 12, color: subTextColor),
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
                child: Text('Cancel', style: GoogleFonts.outfit(color: subTextColor, fontWeight: FontWeight.w600)),
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
                                  content: Text('Complaint status and directives updated successfully.'),
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
                    : Text('Save Updates', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openViewDetailsDialog(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF281710) : Colors.white;
    final fieldBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC);
    final borderCol = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

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
                  Text('Grievance Dossier', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                  Text('$complaintId • Filed $createdAt', style: GoogleFonts.outfit(fontSize: 11.5, color: subTextColor)),
                ],
              ),
            ),
            IconButton(
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
                      child: Text(status.toUpperCase(), style: GoogleFonts.outfit(color: statusCol, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: priorityCol.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: priorityCol.withValues(alpha: 0.3)),
                      ),
                      child: Text('PRIORITY: ${priority.toUpperCase()}', style: GoogleFonts.outfit(color: priorityCol, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const Spacer(),
                    Text('$port • $category', style: GoogleFonts.outfit(fontSize: 11.5, color: subTextColor, fontWeight: FontWeight.w600)),
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
                      Text('Complainant: $name', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
                      const SizedBox(height: 4),
                      Text('Contact: $phone | $email', style: GoogleFonts.inter(fontSize: 12, color: subTextColor)),
                      if (company != 'N/A') ...[
                        const SizedBox(height: 2),
                        Text('Company: $company', style: GoogleFonts.inter(fontSize: 12, color: _kOrange, fontWeight: FontWeight.w500)),
                      ],
                      if (targetEntity.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Target Entity: $targetEntity', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: _kPurple)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Subject & Description
                Text('SUBJECT', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: subTextColor, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(item['subject']?.toString() ?? 'No Subject', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 8),

                Text('DETAILS / GRIEVANCE DESCRIPTION', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: subTextColor, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderCol)),
                  child: Text(description, style: GoogleFonts.inter(fontSize: 12.5, color: textColor, height: 1.4)),
                ),
                const SizedBox(height: 12),

                // Assigned & Resolution
                if (assignedTo.isNotEmpty) ...[
                  Text('Assigned to: $assignedTo', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: subTextColor)),
                  const SizedBox(height: 6),
                ],
                if (resolutionNotes.isNotEmpty) ...[
                  Text('OFFICIAL RESOLUTION DIRECTIVES', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: _kGreen, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: _kGreen.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: _kGreen.withValues(alpha: 0.25))),
                    child: Text(resolutionNotes, style: GoogleFonts.inter(fontSize: 12.5, color: textColor, height: 1.35)),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Close', style: GoogleFonts.outfit(color: subTextColor)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _openUpdateDialog(item);
            },
            icon: const Icon(Icons.edit_note_rounded, size: 16),
            label: Text('Update Case', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12.5)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final borderColor = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final complaints = _displayedComplaints;

    return AppLayout(
      title: 'Complaints',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          AdminHeader(
            title: 'Dispute & Complaint Investigations',
            subtitle: 'Investigate, assign, and resolve trade disputes and broker conduct complaints.',
            actions: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : const Color(0xFF334155),
                  side: BorderSide(color: borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _fetchComplaints,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text('Refresh', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Preserved & Streamlined KPI Cards Row (User requested to keep KPI cards)
          _buildKPIRow(isDark, cardBg, borderColor, textColor, subTextColor),
          const SizedBox(height: 16),

          // Main Complaints Table Section
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.02), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search & Filter Toolbar
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => setState(() {}),
                            style: GoogleFonts.outfit(fontSize: 13.5, color: textColor),
                            decoration: InputDecoration(
                              hintText: 'Search by ID, name, phone, subject, port, entity...',
                              hintStyle: GoogleFonts.inter(fontSize: 12.5, color: subTextColor),
                              prefixIcon: Icon(Icons.search_rounded, size: 16, color: subTextColor),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kOrange, width: 1.2)),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 14),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() {});
                                      },
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterPill('All', 'all', borderColor, textColor),
                            const SizedBox(width: 6),
                            _buildFilterPill('Received', 'Received', borderColor, textColor),
                            const SizedBox(width: 6),
                            _buildFilterPill('Under Review', 'Under Review', borderColor, textColor),
                            const SizedBox(width: 6),
                            _buildFilterPill('Investigating', 'Investigating', borderColor, textColor),
                            const SizedBox(width: 6),
                            _buildFilterPill('Resolved', 'Resolved', borderColor, textColor),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Content
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: List.generate(4, (i) => const Padding(padding: EdgeInsets.only(bottom: 8), child: ShimmerListTile())),
                    ),
                  )
                else if (_hasError)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: _kRed, size: 28),
                          const SizedBox(height: 8),
                          Text('Failed to load complaints', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _fetchComplaints,
                            style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (complaints.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                    child: Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: _kOrange.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.gavel_rounded, size: 28, color: _kOrange),
                          ),
                          const SizedBox(height: 12),
                          Text('No complaints found matching criteria', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                          const SizedBox(height: 4),
                          Text('Logged grievances and disputes will appear here.', style: GoogleFonts.inter(fontSize: 12.5, color: subTextColor)),
                        ],
                      ),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const minWidth = 920.0;
                      final tableWidth = constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: tableWidth),
                          child: DataTable(
                            horizontalMargin: 16,
                            columnSpacing: 18,
                            headingRowHeight: 40,
                            dataRowMinHeight: 52,
                            dataRowMaxHeight: 58,
                            headingRowColor: WidgetStateProperty.all(
                              isDark ? const Color(0xFF381F15) : const Color(0xFFF8FAFC),
                            ),
                            headingTextStyle: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.w700, color: subTextColor),
                            dataTextStyle: GoogleFonts.inter(fontSize: 13, color: textColor),
                            columns: const [
                              DataColumn(label: Text('TRACKING ID')),
                              DataColumn(label: Text('COMPLAINANT')),
                              DataColumn(label: Text('SUBJECT & STATION')),
                              DataColumn(label: Text('STATUS')),
                              DataColumn(label: Text('PRIORITY')),
                              DataColumn(label: Text('ACTIONS')),
                            ],
                            rows: complaints.map((item) {
                              final id = item['complaint_id']?.toString() ?? '';
                              final name = item['name']?.toString() ?? 'Complainant';
                              final phone = item['phone']?.toString() ?? '';
                              final subject = item['subject']?.toString() ?? 'No Subject';
                              final port = item['port']?.toString() ?? 'Tema Port';
                              final category = item['category']?.toString() ?? 'Dispute';
                              final status = item['status']?.toString() ?? 'Received';
                              final priority = item['priority']?.toString() ?? 'Normal';
                              final statusCol = _statusColor(status);
                              final priorityCol = _priorityColor(priority);

                              return DataRow(
                                cells: [
                                  // ID
                                  DataCell(
                                    InkWell(
                                      onTap: () => _openViewDetailsDialog(item),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(color: _kBrown.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                        child: Text(id, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: _kOrange)),
                                      ),
                                    ),
                                  ),
                                  // Complainant
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 180),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(name, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if (phone.isNotEmpty) Text(phone, style: GoogleFonts.inter(fontSize: 11.5, color: subTextColor)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Subject & Station
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 280),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(subject, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          Text('$port • $category', style: GoogleFonts.inter(fontSize: 11.5, color: subTextColor)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Status
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusCol.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: statusCol.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(status.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.w800, color: statusCol)),
                                    ),
                                  ),
                                  // Priority
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: priorityCol.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(priority.toUpperCase(), style: GoogleFonts.outfit(fontSize: 10.5, fontWeight: FontWeight.bold, color: priorityCol)),
                                    ),
                                  ),
                                  // Actions
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ElevatedButton(
                                          onPressed: () => _openViewDetailsDialog(item),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9),
                                            foregroundColor: textColor,
                                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                            minimumSize: Size.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            elevation: 0,
                                          ),
                                          child: Text('Dossier', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 6),
                                        ElevatedButton(
                                          onPressed: () => _openUpdateDialog(item),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _kOrange,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                            minimumSize: Size.zero,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            elevation: 0,
                                          ),
                                          child: Text('Update', style: GoogleFonts.outfit(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),

                // Table Summary Footer
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    'Showing ${complaints.length} of ${_complaints.length} registered grievances',
                    style: GoogleFonts.inter(fontSize: 12, color: subTextColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildKPIRow(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final total = _complaints.length;
    final received = _countForStatus('Received');
    final underReview = _countForStatus('Under Review');
    final investigating = _countForStatus('Investigating');
    final resolved = _countForStatus('Resolved') + _countForStatus('Closed');

    final cards = [
      _buildKPICard('All Cases', '$total', Icons.inbox_rounded, _kBrown, 'all', isDark, cardBg, borderColor, textColor),
      _buildKPICard('Received', '$received', Icons.flag_rounded, _kOrange, 'Received', isDark, cardBg, borderColor, textColor),
      _buildKPICard('Under Review', '$underReview', Icons.assignment_outlined, _kBlue, 'Under Review', isDark, cardBg, borderColor, textColor),
      _buildKPICard('Investigating', '$investigating', Icons.search_rounded, _kPurple, 'Investigating', isDark, cardBg, borderColor, textColor),
      _buildKPICard('Resolved', '$resolved', Icons.check_circle_outline_rounded, _kGreen, 'Resolved', isDark, cardBg, borderColor, textColor),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 780;
        if (isWide) {
          return Row(
            children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c))).toList(),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards.map((c) => Container(width: 155, margin: const EdgeInsets.only(right: 8), child: c)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildKPICard(
    String label,
    String count,
    IconData icon,
    Color color,
    String statusKey,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
  ) {
    final isSelected = _selectedStatus.toLowerCase() == statusKey.toLowerCase();
    return InkWell(
      onTap: () {
        setState(() => _selectedStatus = statusKey);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: isDark ? 0.22 : 0.1) : cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    count,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16, color: textColor),
                  ),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      color: isSelected ? color : Colors.grey,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(
    String label,
    String value,
    Color borderColor,
    Color textColor,
  ) {
    final isSelected = _selectedStatus.toLowerCase() == value.toLowerCase();
    return InkWell(
      onTap: () => setState(() => _selectedStatus = value),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _kBrown : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? _kBrown : borderColor),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : textColor,
          ),
        ),
      ),
    );
  }
}
