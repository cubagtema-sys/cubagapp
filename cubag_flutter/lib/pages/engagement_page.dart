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

  static const _kBrown = Color(0xFF6B3E26);
  static const _kOrange = Color(0xFFFF5000);
  static const _kGreen = Color(0xFF10B981);
  static const _kAmber = Color(0xFFF59E0B);

  final _subjects = [
    {
      'title': 'General Inquiry',
      'desc': 'Questions about CUBAG services, processes, or membership',
    },
    {
      'title': 'License Support',
      'desc': 'Assistance with activations, renewals, or key management',
    },
    {
      'title': 'Payment Issue',
      'desc': 'Help with invoices, billing cycles, or transaction errors',
    },
    {
      'title': 'Event Registration',
      'desc': 'Troubleshoot sign-ups or attendee information',
    },
    {
      'title': 'Technical Problem',
      'desc': 'Bugs, system errors, or accessibility difficulties',
    },
    {
      'title': 'Complaint',
      'desc': 'Formal feedback regarding service quality or experience',
    },
  ];

  final _statusMeta = {
    'open': {
      'color': _kOrange,
      'bg': Color(0x19FF5000),
      'label': 'Open',
    },
    'pending': {
      'color': _kAmber,
      'bg': Color(0x19F59E0B),
      'label': 'Pending',
    },
    'resolved': {
      'color': _kGreen,
      'bg': Color(0x1910B981),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E130D) : Colors.white;
    final border = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final text = isDark ? const Color(0xFFFFF8F3) : const Color(0xFF2B211D);
    final muted = isDark ? const Color(0xFFC8ADA0) : const Color(0xFF6F625B);
    final surfaceRaised = isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);

    return AppLayout(
      title: 'Support & Inquiries',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segmented tab bar (8px radius, quiet border)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: surfaceRaised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 1.0),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _tab = 0),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _tab == 0 ? _kBrown : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.edit_note_rounded,
                            color: _tab == 0 ? Colors.white : muted,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'New Inquiry',
                            style: TextStyle(
                              color: _tab == 0 ? Colors.white : text,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() => _tab = 1);
                      _fetchTickets();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _tab == 1 ? _kBrown : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.confirmation_number_outlined,
                            color: _tab == 1 ? Colors.white : muted,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Archives (${_tickets.length})',
                            style: TextStyle(
                              color: _tab == 1 ? Colors.white : text,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
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

          if (_tab == 0) _buildContactTab(cardBg, border, text, muted, surfaceRaised),
          if (_tab == 1) _buildTicketsTab(cardBg, border, text, muted, surfaceRaised),
        ],
      ),
    );
  }

  Widget _buildContactTab(
    Color cardBg,
    Color border,
    Color text,
    Color muted,
    Color surfaceRaised,
  ) {
    if (_sent) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1.0),
        ),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: _kGreen, size: 48),
            const SizedBox(height: 12),
            Text(
              'Inquiry Recorded',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            if (_newTicketId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: border, width: 1.0),
                ),
                child: Text(
                  'CASE #$_newTicketId',
                  style: const TextStyle(
                    color: _kBrown,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            Text(
              'CUBAG Secretariat will review and respond within 24 hours.',
              style: TextStyle(color: muted, fontSize: 13.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _sent = false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: border, width: 1.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Log Another',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: text,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _tab = 1),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: _kOrange,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'View Archives',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
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
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lodge Inquiry',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: text,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Direct communication with CUBAG executive officers and compliance desk.',
            style: TextStyle(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 18),
          Text(
            'Subject Matter',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: text,
            ),
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
          const SizedBox(height: 16),
          Text(
            'Description / Particulars',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: text,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _msgCtrl,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: text, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Provide details, consignment or reference numbers if applicable...',
              hintStyle: TextStyle(fontSize: 13.5, color: muted.withValues(alpha: 0.7)),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              filled: true,
              fillColor: surfaceRaised,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: border, width: 1.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _kBrown, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed:
                  (_loading || _subject.isEmpty || _msgCtrl.text.trim().isEmpty)
                  ? null
                  : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                disabledBackgroundColor: _kOrange.withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Submit Request',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsTab(
    Color cardBg,
    Color border,
    Color text,
    Color muted,
    Color surfaceRaised,
  ) {
    if (_selectedTicket != null) {
      final sm =
          _statusMeta[_selectedTicket!['status']] ?? _statusMeta['open']!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _selectedTicket = null),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Back to Archives'),
                style: TextButton.styleFrom(
                  foregroundColor: _kBrown,
                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _selectedTicket!['subject']?.toString() ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: text,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: sm['bg'] as Color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (sm['color'] as Color).withValues(alpha: 0.3),
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        (sm['label'] as String).toUpperCase(),
                        style: TextStyle(
                          color: sm['color'] as Color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surfaceRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border, width: 1.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'SUBMITTED BY YOU',
                            style: TextStyle(
                              fontSize: 11,
                              color: muted,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _selectedTicket!['date']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: muted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _selectedTicket!['message']?.toString() ?? '',
                        style: TextStyle(fontSize: 14, color: text, height: 1.4),
                      ),
                    ],
                  ),
                ),
                if (_selectedTicket!['replies'] != null)
                  ...((_selectedTicket!['replies'] as List).map(
                    (r) {
                      final isAdmin = r['author'] == 'Admin';
                      return Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isAdmin
                              ? _kBrown.withValues(alpha: 0.05)
                              : surfaceRaised,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isAdmin ? _kBrown.withValues(alpha: 0.2) : border,
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  isAdmin ? 'CUBAG SECRETARIAT' : '${r['author']}'.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isAdmin ? _kBrown : muted,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  r['date']?.toString() ?? '',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: muted,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              r['message']?.toString() ?? '',
                              style: TextStyle(fontSize: 14, color: text, height: 1.4),
                            ),
                          ],
                        ),
                      );
                    },
                  )),
              ],
            ),
          ),
        ],
      );
    }

    if (_tickets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1.0),
        ),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: muted),
            const SizedBox(height: 10),
            Text(
              'No active inquiries or archives logged.',
              style: TextStyle(color: muted, fontSize: 14, fontWeight: FontWeight.w500),
            ),
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
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${(t['id']?.toString() ?? '').padLeft(5, '0')}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: sm['bg'] as Color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (sm['color'] as Color).withValues(alpha: 0.3),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      (sm['label'] as String).toUpperCase(),
                      style: TextStyle(
                        color: sm['color'] as Color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                t['subject']?.toString() ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: text,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t['message']?.toString() ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Updated: ${t['lastUpdate'] ?? ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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
                      side: BorderSide(color: border, width: 1.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
