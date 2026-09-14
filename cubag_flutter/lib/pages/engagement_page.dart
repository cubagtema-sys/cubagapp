import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/custom_dropdown.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';

class EngagementPage extends StatefulWidget {
  const EngagementPage({super.key});
  @override
  State<EngagementPage> createState() => _EngagementPageState();
}

class _EngagementPageState extends State<EngagementPage> {
  int _tab = 0;
  bool _loading = false;
  bool _sent = false;
  String? _newTicketId;
  String _subject = 'General Inquiry';
  final _msgCtrl = TextEditingController();
  List<dynamic> _tickets = [];
  Map<String, dynamic>? _selectedTicket;

  final _subjects = [
    {
      'title': 'General Inquiry',
      'desc': 'Questions about CUBAG services, processes, or membership',
      'icon': Icons.help_outline_rounded,
      'color': const Color(0xFFFF5000),
      'bg': const Color(0x19FF5000),
    },
    {
      'title': 'License Support',
      'desc': 'Assistance with activations, renewals, or key management',
      'icon': Icons.key_rounded,
      'color': const Color(0xFF8B5CF6),
      'bg': const Color(0x198B5CF6),
    },
    {
      'title': 'Payment Issue',
      'desc': 'Help with invoices, billing cycles, or transaction errors',
      'icon': Icons.payments_rounded,
      'color': const Color(0xFFEC4899),
      'bg': const Color(0x19EC4899),
    },
    {
      'title': 'Event Registration',
      'desc': 'Troubleshoot sign-ups or attendee information',
      'icon': Icons.calendar_today_rounded,
      'color': const Color(0xFF3B82F6),
      'bg': const Color(0x193B82F6),
    },
    {
      'title': 'Technical Problem',
      'desc': 'Bugs, system errors, or accessibility difficulties',
      'icon': Icons.bug_report_rounded,
      'color': const Color(0xFFEF4444),
      'bg': const Color(0x19EF4444),
    },
    {
      'title': 'Complaint',
      'desc': 'Formal feedback regarding service quality or experience',
      'icon': Icons.warning_amber_rounded,
      'color': const Color(0xFF6B7280),
      'bg': const Color(0x196B7280),
    },
  ];

  final _statusMeta = {
    'open': {
      'color': const Color(0xFFFF5000),
      'bg': const Color(0x19FF5000),
      'label': 'Open',
    },
    'pending': {
      'color': const Color(0xFFf59e0b),
      'bg': const Color(0x19f59e0b),
      'label': 'Pending',
    },
    'resolved': {
      'color': const Color(0xFF10b981),
      'bg': const Color(0x1910b981),
      'label': 'Resolved',
    },
  };

  @override
  void initState() {
    super.initState();
    _fetchTickets();
    _msgCtrl.addListener(_onMsgChanged);
  }

  void _onMsgChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_onMsgChanged);
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchTickets() async {
    try {
      final res = await ApiService().get('/tickets');
      if (res.statusCode == 200) {
        setState(() => _tickets = ApiService.ensureList(res.data));
      }
    } catch (e, st) {
      AppLogger.error('engagement_page', e, st);
    }
  }

  Future<void> _submit() async {
    if (_msgCtrl.text.trim().isEmpty || _subject.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService().post(
        '/tickets',
        data: {'subject': _subject, 'message': _msgCtrl.text.trim()},
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          _newTicketId = res.data['id']?.toString();
          _sent = true;
          _tab = 1;
        });
        _msgCtrl.clear();
        _fetchTickets();
      }
    } catch (e, st) {
      AppLogger.error('engagement_page', e, st);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return AppLayout(
      title: 'Support Center',
      child: Column(
        children: [
          // Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _tab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _tab == 0 ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.edit_note,
                            color: _tab == 0 ? Colors.white : Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'New Request',
                            style: TextStyle(
                              color: _tab == 0 ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _tab = 1);
                      _fetchTickets();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _tab == 1 ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.confirmation_number,
                            color: _tab == 1 ? Colors.white : Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'My Tickets (${_tickets.length})',
                            style: TextStyle(
                              color: _tab == 1 ? Colors.white : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_tab == 0) _buildContactTab(primary),
          if (_tab == 1) _buildTicketsTab(primary),
        ],
      ),
    );
  }

  Widget _buildContactTab(Color primary) {
    if (_sent) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF10b981), size: 56),
            const SizedBox(height: 12),
            const Text(
              'Ticket Created',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            if (_newTicketId != null)
              Text(
                '#$_newTicketId',
                style: TextStyle(
                  color: primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: 'monospace',
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              "We'll respond within 24 hours.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => setState(() => _tab = 1),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'View Tickets',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _sent = false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Another Request',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'New Support Ticket',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 16),
          const Text(
            'Subject',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          CustomDropdown<String>(
            value: _subject.isNotEmpty ? _subject : 'General Inquiry',
            hint: 'Select a subject',
            items: _subjects
                .map((s) => DropdownItem<String>(
                      value: s['title'] as String,
                      label: s['title'] as String,
                    ))
                .toList(),
            onChanged: (v) => setState(() => _subject = v),
          ),
          const SizedBox(height: 14),
          const Text(
            'Description',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _msgCtrl,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Explain your issue...',
              hintStyle: const TextStyle(
                fontSize: 15,
                color: Color(0xFF64748b),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed:
                  (_loading || _subject.isEmpty || _msgCtrl.text.trim().isEmpty)
                  ? null
                  : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Submit Ticket',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsTab(Color primary) {
    if (_selectedTicket != null) {
      final sm =
          _statusMeta[_selectedTicket!['status']] ?? _statusMeta['open']!;
      return Column(
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _selectedTicket = null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedTicket!['subject']?.toString() ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: sm['bg'] as Color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        (sm['label'] as String).toUpperCase(),
                        style: TextStyle(
                          color: sm['color'] as Color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOU · ${_selectedTicket!['date'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedTicket!['message']?.toString() ?? '',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ],
                  ),
                ),
                if (_selectedTicket!['replies'] != null)
                  ...((_selectedTicket!['replies'] as List).map(
                    (r) => Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: r['author'] == 'Admin'
                            ? primary.withValues(alpha: 0.05)
                            : Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['author']} · ${r['date'] ?? ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: r['author'] == 'Admin'
                                  ? primary
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            r['message']?.toString() ?? '',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  )),
              ],
            ),
          ),
        ],
      );
    }

    if (_tickets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(60),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.confirmation_number, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No tickets yet.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: _tickets.map((t) {
        final sm = _statusMeta[t['status']] ?? _statusMeta['open']!;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${(t['id']?.toString() ?? '').padLeft(6, '0')}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: sm['bg'] as Color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      (sm['label'] as String).toUpperCase(),
                      style: TextStyle(
                        color: sm['color'] as Color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                t['subject']?.toString() ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t['message']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Updated: ${t['lastUpdate'] ?? ''}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => setState(
                      () => _selectedTicket = Map<String, dynamic>.from(t),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('View', style: TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
