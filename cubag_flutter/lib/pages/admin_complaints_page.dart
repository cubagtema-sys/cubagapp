import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

// Brand & semantic colors
const _kBrown = Color(0xFF6B3E26);
const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kBlue = Color(0xFF3B82F6);
const _kPurple = Color(0xFF8B5CF6);
const _kRed = Color(0xFFEF4444);

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
  bool _isTableView = true; // Default to table view for compact representation
  final Set<String> _expandedIds = {};

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
        if (!id.contains(query) &&
            !name.contains(query) &&
            !subject.contains(query) &&
            !phone.contains(query) &&
            !port.contains(query) &&
            !desc.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  void _toggleExpandAll() {
    setState(() {
      if (_expandedIds.length == _complaints.length) {
        _expandedIds.clear();
      } else {
        _expandedIds.addAll(
          _complaints.map((c) => c['complaint_id']?.toString() ?? ''),
        );
      }
    });
  }

  void _openUpdateDialog(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final fieldBg = isDark ? const Color(0xFF281710) : const Color(0xFFF8F4F0);
    final borderCol = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFE8DED6);
    final textColor = isDark ? Colors.white : const Color(0xFF2B211D);
    final subTextColor = isDark
        ? Colors.grey.shade400
        : const Color(0xFF6F625B);

    String status = item['status']?.toString() ?? 'Received';
    String priority = item['priority']?.toString() ?? 'Normal';
    final notesCtrl = TextEditingController(
      text: item['resolution_notes']?.toString() ?? '',
    );
    final assignedCtrl = TextEditingController(
      text:
          item['assigned_to']?.toString() ?? 'Secretariat Grievance Committee',
    );
    bool saving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          return AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kBrown.withValues(alpha: isDark ? 0.4 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.gavel_rounded,
                    color: _kOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Update Complaint',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['complaint_id']?.toString() ?? '',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: _kOrange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Complainant info banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderCol),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subject: ${item['subject'] ?? ''}',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 14,
                                color: subTextColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Complainant: ${item['name'] ?? ''} (${item['phone'] ?? ''})',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: subTextColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.anchor_rounded,
                                size: 14,
                                color: subTextColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Station: ${item['port'] ?? ''} · Category: ${item['category'] ?? ''}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: subTextColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (item['target_entity'] != null &&
                              item['target_entity'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.business_outlined,
                                  size: 14,
                                  color: _kOrange,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Entity Involved: ${item['target_entity']}',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: _kOrange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Status Dropdown
                    Text(
                      'Grievance Status *',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderCol),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: status,
                          isExpanded: true,
                          dropdownColor: dialogBg,
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 13.5,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Received',
                              child: Text('Received (Logged into Registry)'),
                            ),
                            DropdownMenuItem(
                              value: 'Under Review',
                              child: Text(
                                'Under Review (Secretariat Assessment)',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Investigating',
                              child: Text('Investigating (Port Verification)'),
                            ),
                            DropdownMenuItem(
                              value: 'Resolved',
                              child: Text(
                                'Resolved (Resolution Notice Issued)',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Closed',
                              child: Text('Closed (Dismissed / Finalized)'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => status = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Priority
                    Text(
                      'Priority Level',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderCol),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: priority,
                          isExpanded: true,
                          dropdownColor: dialogBg,
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 13.5,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Normal',
                              child: Text('Normal Priority'),
                            ),
                            DropdownMenuItem(
                              value: 'High',
                              child: Text('High Priority'),
                            ),
                            DropdownMenuItem(
                              value: 'Urgent',
                              child: Text('Urgent Disciplinary Priority'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setModalState(() => priority = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Assigned Handler / Committee
                    Text(
                      'Assigned Committee / Officer',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: assignedCtrl,
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        color: textColor,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. Secretariat Grievance Committee',
                        hintStyle: GoogleFonts.outfit(
                          fontSize: 13,
                          color: subTextColor,
                        ),
                        filled: true,
                        fillColor: fieldBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _kOrange,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Resolution Notes
                    Text(
                      'Official Resolution Notice & Directives',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 4,
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        color: textColor,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Enter formal Secretariat findings, hearing dates, or corrective directives (visible to complainant on tracking portal)...',
                        hintStyle: GoogleFonts.outfit(
                          fontSize: 12.5,
                          color: subTextColor,
                        ),
                        filled: true,
                        fillColor: fieldBg,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderCol),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _kOrange,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.outfit(
                    color: subTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                                  content: Text(
                                    'Complaint status and resolution updated successfully.',
                                  ),
                                ),
                              );
                            }
                          } else {
                            setModalState(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: _kRed,
                                  content: Text(
                                    'Failed to update complaint status. Please try again.',
                                  ),
                                ),
                              );
                            }
                          }
                        } catch (e, st) {
                          AppLogger.error('admin_complaints_update', e, st);
                          setModalState(() => saving = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Save Updates',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openViewDetailsDialog(Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final fieldBg = isDark ? const Color(0xFF281710) : const Color(0xFFF8F4F0);
    final borderCol = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE8DED6);
    final textColor = isDark ? Colors.white : const Color(0xFF2B211D);
    final subTextColor = isDark ? Colors.grey.shade400 : const Color(0xFF6F625B);

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

    Color statusColor = _kOrange;
    if (status.toLowerCase() == 'resolved') statusColor = _kGreen;
    if (status.toLowerCase() == 'under review') statusColor = _kBlue;
    if (status.toLowerCase() == 'investigating') statusColor = _kPurple;
    if (status.toLowerCase() == 'closed') statusColor = Colors.grey;

    Color priorityColor = Colors.grey;
    if (priority.toLowerCase() == 'urgent') priorityColor = _kRed;
    if (priority.toLowerCase() == 'high') priorityColor = _kOrange;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kOrange.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.description_rounded, color: _kOrange, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Complaint Dossier & Details',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        complaintId,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: _kOrange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• Filed on $createdAt',
                        style: GoogleFonts.inter(fontSize: 11.5, color: subTextColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              color: Colors.grey,
              onPressed: () => Navigator.pop(dialogCtx),
            ),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status & Priority Bar
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(isDark ? 60 : 30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 8, color: statusColor),
                          const SizedBox(width: 6),
                          Text(
                            status.toUpperCase(),
                            style: GoogleFonts.outfit(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: priorityColor.withAlpha(isDark ? 60 : 30),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: priorityColor.withAlpha(80)),
                      ),
                      child: Text(
                        'PRIORITY: ${priority.toUpperCase()}',
                        style: GoogleFonts.outfit(
                          color: priorityColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderCol),
                      ),
                      child: Text(
                        '$port • $category',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: subTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Complainant & Subject Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderCol),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMPLAINANT PROFILE',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _kOrange,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: textColor,
                                  ),
                                ),
                                if (company != 'N/A')
                                  Text(
                                    company,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: subTextColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                phone,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                  color: textColor,
                                ),
                              ),
                              Text(
                                email,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: subTextColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Target Entity (If Any)
                if (targetEntity.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _kOrange.withAlpha(isDark ? 30 : 15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kOrange.withAlpha(60)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ACCUSED / TARGET ENTITY',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _kOrange,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          targetEntity,
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Full Complaint Narrative Statement
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: fieldBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderCol),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'COMPLAINT STATEMENT & EVIDENCE NARRATIVE',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: textColor.withAlpha(180),
                              letterSpacing: 0.8,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.grey),
                            tooltip: 'Copy Statement',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: description));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Complaint statement copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        description,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: textColor,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Administrative & Resolution Status
                if (resolutionNotes.isNotEmpty || assignedTo.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: fieldBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SECRETARIAT RESOLUTION & INTERNAL AUDIT',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _kGreen,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Assigned Officer: $assignedTo',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        if (resolutionNotes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            resolutionNotes,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: subTextColor,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Close',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _openUpdateDialog(item);
            },
            icon: const Icon(Icons.edit_note_rounded, size: 16),
            label: Text(
              'Update Resolution',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF4D2D20)
        : const Color(0xFFE8DED6);
    final textColor = isDark ? Colors.white : const Color(0xFF2B211D);
    final subTextColor = isDark
        ? Colors.grey.shade400
        : const Color(0xFF6F625B);

    final allExpanded =
        _complaints.isNotEmpty && _expandedIds.length == _complaints.length;

    return AppLayout(
      title: 'Complaints',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminHeader(
            title: 'Dispute & Complaint Investigations',
            subtitle:
                'Investigate, assign, and resolve trade disputes and broker conduct complaints.',
            actions: [
              // View Toggle
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF281710)
                      : const Color(0xFFF8F4F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _isTableView = true),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(9),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _isTableView
                              ? kAdminBrown
                              : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(9),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.table_rows_rounded,
                              size: 16,
                              color: _isTableView ? Colors.white : subTextColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Table',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _isTableView
                                    ? Colors.white
                                    : subTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _isTableView = false),
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(9),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: !_isTableView
                              ? kAdminBrown
                              : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(9),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.grid_view_rounded,
                              size: 16,
                              color: !_isTableView
                                  ? Colors.white
                                  : subTextColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Cards',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: !_isTableView
                                    ? Colors.white
                                    : subTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Expand/Collapse All (if table view)
              if (_isTableView && _complaints.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _toggleExpandAll,
                  icon: Icon(
                    allExpanded
                        ? Icons.unfold_less_rounded
                        : Icons.unfold_more_rounded,
                    size: 16,
                    color: textColor,
                  ),
                  label: Text(
                    allExpanded ? 'Collapse All' : 'Expand All',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),

              // Refresh Button
              ElevatedButton.icon(
                onPressed: _loading ? null : _fetchComplaints,
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  'Refresh',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAdminOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // KPI Cards
          _buildKPIRow(isDark, cardBg, borderColor, textColor, subTextColor),
          const SizedBox(height: 20),

          // Filter & Search Bar
          _buildSearchBar(isDark, cardBg, borderColor, textColor, subTextColor),
          const SizedBox(height: 20),

          // Content Area
          if (_loading)
            _buildLoadingState(isDark, cardBg, borderColor)
          else if (_hasError)
            _buildErrorState(
              isDark,
              cardBg,
              borderColor,
              textColor,
              subTextColor,
            )
          else if (_displayedComplaints.isEmpty)
            _buildEmptyState(
              isDark,
              cardBg,
              borderColor,
              textColor,
              subTextColor,
            )
          else if (_isTableView)
            _buildComplaintsTable(
              isDark,
              cardBg,
              borderColor,
              textColor,
              subTextColor,
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _displayedComplaints.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (ctx, i) {
                final item = _displayedComplaints[i];
                return _buildComplaintCard(
                  item,
                  isDark,
                  cardBg,
                  borderColor,
                  textColor,
                  subTextColor,
                );
              },
            ),
          const SizedBox(height: 32),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        final kpiCards = [
          _kpiCard(
            'All',
            '$total',
            Icons.inbox_rounded,
            _kBrown,
            'all',
            isDark,
            cardBg,
            borderColor,
            textColor,
          ),
          _kpiCard(
            'Received',
            '$received',
            Icons.flag_rounded,
            _kOrange,
            'Received',
            isDark,
            cardBg,
            borderColor,
            textColor,
          ),
          _kpiCard(
            'Under Review',
            '$underReview',
            Icons.assignment_outlined,
            _kBlue,
            'Under Review',
            isDark,
            cardBg,
            borderColor,
            textColor,
          ),
          _kpiCard(
            'Investigating',
            '$investigating',
            Icons.search_rounded,
            _kPurple,
            'Investigating',
            isDark,
            cardBg,
            borderColor,
            textColor,
          ),
          _kpiCard(
            'Resolved',
            '$resolved',
            Icons.check_circle_outline_rounded,
            _kGreen,
            'Resolved',
            isDark,
            cardBg,
            borderColor,
            textColor,
          ),
        ];

        if (isNarrow) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: kpiCards
                  .map(
                    (c) => Container(
                      width: 140,
                      margin: const EdgeInsets.only(right: 10),
                      child: c,
                    ),
                  )
                  .toList(),
            ),
          );
        }

        return Row(
          children: kpiCards
              .map(
                (c) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: c,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _kpiCard(
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.25 : 0.12)
              : cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : borderColor,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.3 : 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: textColor,
                    ),
                  ),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      color: isSelected ? color : Colors.grey,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
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

  Widget _buildSearchBar(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return AdminToolbar(
      searchController: _searchCtrl,
      searchHint: 'Search by ID, name, phone, subject, or port...',
      onSearchChanged: (_) => setState(() {}),
      onSearchClear: () {
        _searchCtrl.clear();
        setState(() {});
      },
      filters: [
        _statusFilterChip('all', 'All Statuses', borderColor, textColor),
        _statusFilterChip('Received', 'Received', borderColor, textColor),
        _statusFilterChip(
          'Under Review',
          'Under Review',
          borderColor,
          textColor,
        ),
        _statusFilterChip(
          'Investigating',
          'Investigating',
          borderColor,
          textColor,
        ),
        _statusFilterChip('Resolved', 'Resolved', borderColor, textColor),
        _statusFilterChip('Closed', 'Closed', borderColor, textColor),
      ],
      trailing: ElevatedButton(
        onPressed: _fetchComplaints,
        style: ElevatedButton.styleFrom(
          backgroundColor: kAdminOrange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Text(
          'Search',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  Widget _statusFilterChip(
    String value,
    String label,
    Color borderColor,
    Color textColor,
  ) {
    final isSelected = _selectedStatus.toLowerCase() == value.toLowerCase();
    return InkWell(
      onTap: () {
        setState(() => _selectedStatus = value);
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? _kBrown : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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

  // ── DATA TABLE VIEW (Dense, Collapsible, Multi-item view) ───────────────────
  Widget _buildComplaintsTable(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final headerBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8F4F0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const minTableWidth = 1020.0;
            final tableWidth = constraints.maxWidth > minTableWidth
                ? constraints.maxWidth
                : minTableWidth;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Table Header Row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: headerBg,
                        border: Border(
                          bottom: BorderSide(color: borderColor, width: 1.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          _buildTableHeaderCell('TRACKING ID', 2, textColor),
                          _buildTableHeaderCell('COMPLAINANT', 2, textColor),
                          _buildTableHeaderCell(
                            'SUBJECT',
                            3,
                            textColor,
                          ),
                          _buildTableHeaderCell(
                            'CATEGORY & PORT',
                            2,
                            textColor,
                          ),
                          _buildTableHeaderCell(
                            'STATUS / PRIORITY',
                            2,
                            textColor,
                          ),
                          _buildTableHeaderCell(
                            'ACTIONS',
                            2,
                            textColor,
                            align: TextAlign.right,
                          ),
                        ],
                      ),
                    ),

                    // Table Body Rows
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _displayedComplaints.length,
                      itemBuilder: (context, index) {
                        final item = _displayedComplaints[index];
                        final isLast = index == _displayedComplaints.length - 1;
                        return _buildTableRow(
                          item,
                          index,
                          isLast,
                          isDark,
                          cardBg,
                          borderColor,
                          textColor,
                          subTextColor,
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTableHeaderCell(
    String label,
    int flex,
    Color textColor, {
    TextAlign align = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: textColor.withValues(alpha: 0.7),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildTableRow(
    Map<String, dynamic> item,
    int index,
    bool isLast,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final complaintId = item['complaint_id']?.toString() ?? '';
    final isExpanded = _expandedIds.contains(complaintId);
    final status = item['status']?.toString() ?? 'Received';
    final priority = item['priority']?.toString() ?? 'Normal';
    final rowBg = isExpanded
        ? (isDark ? const Color(0xFF281710) : const Color(0xFFF8F4F0))
        : (index.isEven
              ? cardBg
              : (isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF8F4F0)));

    Color statusColor = _kOrange;
    if (status.toLowerCase() == 'resolved') statusColor = _kGreen;
    if (status.toLowerCase() == 'under review') statusColor = _kBlue;
    if (status.toLowerCase() == 'investigating') statusColor = _kPurple;
    if (status.toLowerCase() == 'closed') statusColor = Colors.grey;

    Color priorityColor = Colors.grey;
    if (priority.toLowerCase() == 'urgent') priorityColor = _kRed;
    if (priority.toLowerCase() == 'high') priorityColor = _kOrange;

    return Column(
      children: [
        InkWell(
          onTap: () => _toggleExpand(complaintId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: rowBg,
              border: isLast && !isExpanded
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: borderColor.withValues(alpha: 0.6),
                      ),
                    ),
            ),
            child: Row(
              children: [
                // 1. Complaint ID & Date
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            complaintId,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: _kOrange,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(
                              Icons.copy_rounded,
                              size: 13,
                              color: Colors.grey,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Copy ID',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: complaintId),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Copied $complaintId to clipboard',
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      Text(
                        item['created_at']?.toString().split('T').first ?? '',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: subTextColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Complainant
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item['name']?.toString() ?? '',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item['phone']?.toString() ??
                            item['email']?.toString() ??
                            '',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          color: subTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 3. Subject
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item['subject']?.toString() ?? '',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item['category'] != null &&
                          item['category'].toString().isNotEmpty)
                        Text(
                          item['category']?.toString() ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: subTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // 4. Port & Location
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item['port']?.toString() ?? 'Tema Port',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Ghana Ports',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: subTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 5. Status & Priority
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(
                            alpha: isDark ? 0.25 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (priority.toLowerCase() != 'normal') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: priorityColor.withValues(
                              alpha: isDark ? 0.25 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            priority.toUpperCase(),
                            style: GoogleFonts.outfit(
                              color: priorityColor,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 6. Actions (View & Update)
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _openViewDetailsDialog(item),
                        icon: const Icon(Icons.visibility_rounded, size: 13, color: _kOrange),
                        label: Text(
                          'View',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kOrange,
                          side: const BorderSide(color: _kOrange, width: 1.2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () => _openUpdateDialog(item),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBrown,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Update',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── COLLAPSED / EXPANDED INLINE DETAILS ───────────────────────────────
        if (isExpanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF281710) : const Color(0xFFF8F4F0),
              border: Border(
                bottom: BorderSide(color: borderColor, width: 1.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FULL COMPLAINT DETAILS',
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: _kOrange,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item['description']?.toString() ??
                                'No description provided.',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: textColor,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [
                              _metaChip(
                                Icons.email_outlined,
                                'Email: ${item['email'] ?? 'N/A'}',
                                subTextColor,
                              ),
                              _metaChip(
                                Icons.phone_outlined,
                                'Phone: ${item['phone'] ?? 'N/A'}',
                                subTextColor,
                              ),
                              if (item['target_entity'] != null &&
                                  item['target_entity'].toString().isNotEmpty)
                                _metaChip(
                                  Icons.business_outlined,
                                  'Accused/Target: ${item['target_entity']}',
                                  _kOrange,
                                ),
                              _metaChip(
                                Icons.person_pin_outlined,
                                'Handler: ${item['assigned_to'] ?? 'Secretariat Committee'}',
                                subTextColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SECRETARIAT RESOLUTION DIRECTIVES',
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: _kGreen,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (item['resolution_notes'] != null &&
                              item['resolution_notes']
                                  .toString()
                                  .trim()
                                  .isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _kGreen.withValues(
                                  alpha: isDark ? 0.2 : 0.1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _kGreen.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.verified_outlined,
                                    size: 16,
                                    color: _kGreen,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item['resolution_notes'].toString(),
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        color: textColor,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Text(
                              'No resolution directive logged yet. Click "Update" to issue findings or record mediation progress.',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: subTextColor,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: () => _openUpdateDialog(item),
                              icon: const Icon(
                                Icons.edit_note_rounded,
                                size: 15,
                              ),
                              label: Text(
                                'Update Directives & Status',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kOrange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLoadingState(bool isDark, Color cardBg, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(color: _kOrange),
          const SizedBox(height: 16),
          Text(
            'Loading Complaints...',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    subTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(36),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: _kRed),
          const SizedBox(height: 12),
          Text(
            'Failed to load complaints registry.',
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Please check your internet connection or backend server status.',
            style: GoogleFonts.outfit(fontSize: 13, color: subTextColor),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchComplaints,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(
              'Try Again',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBrown,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(48),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 56,
            color: subTextColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          Text(
            'No complaints found.',
            style: GoogleFonts.outfit(
              fontSize: 17,
              color: textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedStatus != 'all'
                ? 'There are currently no complaints logged under "$_selectedStatus".'
                : 'No dispute or conduct complaints have been lodged into the registry yet.',
            style: GoogleFonts.outfit(fontSize: 13, color: subTextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildComplaintCard(
    Map<String, dynamic> item,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final status = item['status']?.toString() ?? 'Received';
    final priority = item['priority']?.toString() ?? 'Normal';
    final complaintId = item['complaint_id']?.toString() ?? '';

    Color statusColor = _kOrange;
    if (status.toLowerCase() == 'resolved') statusColor = _kGreen;
    if (status.toLowerCase() == 'under review') statusColor = _kBlue;
    if (status.toLowerCase() == 'investigating') statusColor = _kPurple;
    if (status.toLowerCase() == 'closed') statusColor = Colors.grey;

    Color priorityColor = Colors.grey;
    if (priority.toLowerCase() == 'urgent') priorityColor = _kRed;
    if (priority.toLowerCase() == 'high') priorityColor = _kOrange;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: ID, Status, Priority, Update Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Complaint ID with copy
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: complaintId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Copied $complaintId to clipboard',
                                ),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _kBrown.withValues(
                                alpha: isDark ? 0.3 : 0.08,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _kBrown.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  complaintId,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: _kOrange,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.copy_rounded,
                                  size: 12,
                                  color: _kOrange,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(
                              alpha: isDark ? 0.25 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: GoogleFonts.outfit(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),

                        // Priority Tag
                        if (priority.toLowerCase() != 'normal')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: priorityColor.withValues(
                                alpha: isDark ? 0.25 : 0.12,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: priorityColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 12,
                                  color: priorityColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  priority.toUpperCase(),
                                  style: GoogleFonts.outfit(
                                    color: priorityColor,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item['subject']?.toString() ?? '',
                      style: GoogleFonts.outfit(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openUpdateDialog(item),
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: Text(
                  'Update Status',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrown,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            item['description']?.toString() ?? '',
            style: GoogleFonts.outfit(
              fontSize: 13.5,
              color: subTextColor,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Divider(color: borderColor),
          const SizedBox(height: 10),

          // Metadata Row
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _metaChip(
                Icons.person_outline_rounded,
                'Complainant: ${item['name'] ?? ''} (${item['phone'] ?? ''})',
                subTextColor,
              ),
              _metaChip(
                Icons.email_outlined,
                item['email'] ?? '',
                subTextColor,
              ),
              _metaChip(
                Icons.anchor_rounded,
                'Port: ${item['port'] ?? ''}',
                subTextColor,
              ),
              _metaChip(
                Icons.category_outlined,
                'Category: ${item['category'] ?? ''}',
                subTextColor,
              ),
              if (item['target_entity'] != null &&
                  item['target_entity'].toString().isNotEmpty)
                _metaChip(
                  Icons.business_outlined,
                  'Entity: ${item['target_entity']}',
                  _kOrange,
                ),
              _metaChip(
                Icons.calendar_today_outlined,
                'Logged: ${item['created_at']?.toString().split('T').first ?? ''}',
                subTextColor,
              ),
            ],
          ),

          // Official Secretariat Resolution Note if available
          if (item['resolution_notes'] != null &&
              item['resolution_notes'].toString().trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.verified_outlined, size: 18, color: _kGreen),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Secretariat Resolution & Directives',
                              style: GoogleFonts.outfit(
                                fontSize: 12.5,
                                color: _kGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (item['assigned_to'] != null &&
                                item['assigned_to'].toString().isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '· Handler: ${item['assigned_to']}',
                                style: GoogleFonts.outfit(
                                  fontSize: 11.5,
                                  color: subTextColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item['resolution_notes'].toString(),
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: textColor,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text, Color color) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(text, style: GoogleFonts.outfit(fontSize: 12.5, color: color)),
      ],
    );
  }
}
