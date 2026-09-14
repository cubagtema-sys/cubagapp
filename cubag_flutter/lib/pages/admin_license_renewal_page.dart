import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import '../components/shimmer_loader.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kRed = Color(0xFFef4444);
const _kAmber = Color(0xFFf59e0b);

const _durationPresets = [
  {'label': '1 Month', 'months': 1},
  {'label': '3 Months', 'months': 3},
  {'label': '6 Months', 'months': 6},
  {'label': '1 Year', 'months': 12},
];

String _addMonths(int months) {
  final d = DateTime.now();
  var year = d.year + (d.month - 1 + months) ~/ 12;
  var month = (d.month - 1 + months) % 12 + 1;
  return '$year-${month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _fmt(String? str) {
  if (str == null || str.isEmpty) return '—';
  try {
    final d = DateTime.parse(str);
    return '${d.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]} ${d.year}';
  } catch (_) {
    return str;
  }
}

class AdminLicenseRenewalPage extends StatefulWidget {
  const AdminLicenseRenewalPage({super.key});
  @override
  State<AdminLicenseRenewalPage> createState() => _State();
}

class _State extends State<AdminLicenseRenewalPage> {
  final _api = ApiService();
  List<dynamic> _members = [];
  bool _loading = true;
  bool _hasError = false;
  String _tab = 'pending';
  Map<String, dynamic> _msg = {'text': '', 'ok': true};
  dynamic _selectedPayment;

  // Per-member editor state: {id: {preset: int?, customDate: '', saving: bool}}
  final Map<int, Map<String, dynamic>> _editors = {};
  final Map<int, List<dynamic>> _histories = {};
  final Map<int, bool> _showHistory = {};

  int _page = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetch();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_loading && !_loadingMore && _hasMore) {
        _fetchMore();
      }
    }
  }

  Future<void> _fetch({bool refresh = false}) async {
    if (!mounted) return;
    if (refresh) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _loading = true;
        _members = [];
      });
    } else {
      if (!_loading) setState(() => _loading = true);
    }

    final fetchTab = _tab;
    await _api.fetchDataWithCache(
      'members/admin/all?page=$_page&limit=20&status=$fetchTab',
      (data, isCached, {bool hasError = false}) {
        if (!mounted) return;
        if (_tab != fetchTab) return;
        if (hasError && _members.isEmpty) {
          setState(() {
            _loading = false;
            _hasError = true;
          });
          return;
        }
        if (data == null) {
          setState(() => _loading = false);
          return;
        }
        setState(() {
          _loading = false;
          if (data is Map) {
            _members = ApiService.ensureList(data);
            if (data.containsKey('total')) {
              _total = data['total'];
              _hasMore = _members.length < _total;
            } else {
              _hasMore = false;
            }
          } else if (data is List) {
            _members = data;
            _hasMore = false;
          }

          for (final m in _members) {
            final id = m['id'] as int;
            if (!_editors.containsKey(id)) {
              final exp =
                  m['license_expiry_date']?.toString().split('T')[0] ?? '';
              _editors[id] = {
                'preset': null,
                'customDate': exp,
                'saving': false,
              };
            }
          }
        });
      },
    );
  }

  Future<void> _fetchMore() async {
    setState(() => _loadingMore = true);
    _page++;
    final data = await _api.fetchData(
      'members/admin/all?page=$_page&limit=20&status=$_tab',
    );
    if (mounted) {
      setState(() {
        _loadingMore = false;
        if (data is Map) {
          final newItems = ApiService.ensureList(data);
          _members.addAll(newItems);
          if (data.containsKey('total')) {
            _hasMore = _members.length < data['total'];
          } else {
            _hasMore = newItems.isNotEmpty;
          }
        }

        for (final m in _members) {
          final id = m['id'] as int;
          if (!_editors.containsKey(id)) {
            final exp =
                m['license_expiry_date']?.toString().split('T')[0] ?? '';
            _editors[id] = {'preset': null, 'customDate': exp, 'saving': false};
          }
        }
      });
    }
  }

  Future<void> _updateStatus(int id, String status) async {
    await _api.putData('members/admin/status/$id', {'status': status});
    await _fetch();
    setState(
      () => _msg = {
        'text': status == 'active' ? 'Member approved ✓' : 'Member rejected.',
        'ok': true,
      },
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _msg = {'text': '', 'ok': true});
    });
  }

  Future<void> _toggleHistory(int memberId) async {
    final nowShowing = !(_showHistory[memberId] ?? false);
    setState(() => _showHistory[memberId] = nowShowing);
    if (nowShowing && !_histories.containsKey(memberId)) {
      final data = await _api.fetchData(
        'members/admin/license-history/$memberId',
      );
      if (mounted && data is List) setState(() => _histories[memberId] = data);
    }
  }

  Future<void> _saveExpiry(dynamic member) async {
    final id = member['id'] as int;
    final ed = _editors[id]!;
    String? expiryDate;
    String durationLabel = '';
    if (ed['preset'] != null) {
      expiryDate = _addMonths(ed['preset'] as int);
      durationLabel =
          _durationPresets.firstWhere(
                (p) => p['months'] == ed['preset'],
              )['label']
              as String;
    } else if ((ed['customDate'] as String).isNotEmpty) {
      expiryDate = ed['customDate'] as String;
      durationLabel = 'Custom';
    }
    if (expiryDate == null) return;

    setState(() => _editors[id]!['saving'] = true);
    final today = DateTime.now();
    await _api.putData('members/admin/set-expiry/$id', {
      'license_expiry_date': expiryDate,
      'duration_label': durationLabel,
      'start_date':
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
    });
    _histories.remove(id); // clear cached history
    await _fetch();
    setState(() {
      _editors[id]!['saving'] = false;
      _msg = {
        'text':
            '$durationLabel period set for ${member['name']}. Old license archived.',
        'ok': true,
      };
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _msg = {'text': '', 'ok': true});
    });
  }

  List<dynamic> get _pendingList => _members;
  List<dynamic> get _activeList => _members;

  @override
  Widget build(BuildContext context) => AppLayout(
    title: 'Renewals',
    scrollable: false,
    child: Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminHeader(
              title: 'Licensing & Membership Renewals',
              subtitle:
                  'Manage member license validity, expiry date updates, and renewal approvals.',
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _fetch(refresh: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    'Refresh',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Tab bar
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF281710)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _tabBtn('pending', 'Pending Approvals'),
                  _tabBtn('active', 'Active Licenses'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if ((_msg['text'] as String).isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_msg['ok'] == true ? _kGreen : _kRed).withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _msg['text'] as String,
                  style: TextStyle(
                    color: _msg['ok'] == true ? _kGreen : _kRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children: [
                    if (_loading)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 8,
                        separatorBuilder: (ctx, i) =>
                            const SizedBox(height: 12),
                        itemBuilder: (ctx, i) => const ShimmerListTile(),
                      ),
                    if (!_loading && _hasError && _members.isEmpty)
                      FetchErrorView(onRetry: () => _fetch(refresh: true)),
                    if (!_loading && !_hasError && _tab == 'pending')
                      _buildPendingTab(),
                    if (!_loading && !_hasError && _tab == 'active')
                      _buildActiveTab(),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Payment sheet
        if (_selectedPayment != null) _buildPaymentSheet(),
      ],
    ),
  );

  Widget _tabBtn(String id, String label) => Expanded(
    child: GestureDetector(
      onTap: () {
        if (_tab != id) {
          setState(() => _tab = id);
          _fetch(refresh: true);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _tab == id ? _kOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: _tab == id ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    ),
  );

  Widget _buildPendingTab() {
    if (_pendingList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text(
            'No pending renewals.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return Column(
      children: [
        ..._pendingList.map(
          (m) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m['name'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                            ),
                          ),
                          Text(
                            '${m['company'] ?? 'Independent'} · ${m['port_of_operation'] ?? '—'}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _kAmber.withAlpha(30),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'PENDING',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _kAmber,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _infoTile('License', m['license_number'] ?? 'TBD'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _infoTile(
                        'Ref',
                        m['payment_ref'] ?? 'N/A',
                        mono: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _selectedPayment = m),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kOrange,
                          side: const BorderSide(color: _kOrange),
                        ),
                        child: const Text(
                          'Verify Pay',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _updateStatus(m['id'], 'active'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Approve',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_loadingMore)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: _kOrange),
            ),
          ),
        if (!_loading && _total > 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                '${_members.length} members shown${_total > 0 ? " of $_total" : ""}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActiveTab() {
    if (_activeList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text(
            'No active members yet.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return Column(
      children: [
        ..._activeList.map((m) {
          final id = m['id'] as int;
          final ed =
              _editors[id] ??
              {'preset': null, 'customDate': '', 'saving': false};
          final exp = m['license_expiry_date']?.toString().split('T')[0];
          final now = DateTime.now();
          final expDt = exp != null ? DateTime.tryParse(exp) : null;
          final isExpired = expDt != null && expDt.isBefore(now);
          final isSoon =
              expDt != null && !isExpired && expDt.difference(now).inDays < 30;

          String? previewDate;
          if (ed['preset'] != null) {
            previewDate = _addMonths(ed['preset'] as int);
          } else if ((ed['customDate'] as String).isNotEmpty) {
            previewDate = ed['customDate'] as String;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m['name'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            m['license_number'] ?? 'No license #',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        if (isExpired) _badge('EXPIRED', _kRed),
                        if (isSoon) _badge('EXPIRING SOON', _kAmber),
                        _badge(
                          m['status']?.toString().toUpperCase() ?? '',
                          m['status'] == 'active' ? _kGreen : _kRed,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Current Expiry',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        exp != null ? _fmt(exp) : 'Not set',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isExpired
                              ? _kRed
                              : isSoon
                              ? _kAmber
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'SET DURATION — starts from today',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._durationPresets.map((p) {
                      final selected = ed['preset'] == p['months'];
                      return GestureDetector(
                        onTap: () => setState(
                          () => _editors[id]!['preset'] = p['months'],
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? _kOrange : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected ? _kOrange : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            p['label'] as String,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? Colors.white
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _editors[id]!['preset'] = null),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: ed['preset'] == null
                              ? _kOrange
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: ed['preset'] == null
                                ? _kOrange
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          'Custom',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ed['preset'] == null
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (ed['preset'] == null) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(
                          const Duration(days: 30),
                        ),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2099),
                      );
                      if (picked != null) {
                        setState(
                          () => _editors[id]!['customDate'] =
                              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            (ed['customDate'] as String).isEmpty
                                ? 'Pick custom date'
                                : _fmt(ed['customDate'] as String),
                            style: TextStyle(
                              color: (ed['customDate'] as String).isEmpty
                                  ? Colors.grey
                                  : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (previewDate != null)
                      Expanded(
                        child: Text(
                          '→ Expires: ${_fmt(previewDate)}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: _kGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: ed['saving'] == true || previewDate == null
                          ? null
                          : () => _saveExpiry(m),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        ed['saving'] == true ? 'Saving…' : 'Apply & Save',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: Icon(
                    _showHistory[id] == true
                        ? Icons.expand_less
                        : Icons.history,
                    size: 16,
                  ),
                  label: Text(
                    '${_showHistory[id] == true ? 'Hide' : 'View'} License History',
                    style: const TextStyle(fontSize: 16),
                  ),
                  onPressed: () => _toggleHistory(id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                    side: BorderSide(color: Colors.grey.shade300),
                    minimumSize: const Size(double.infinity, 36),
                  ),
                ),
                if (_showHistory[id] == true) ...[
                  const SizedBox(height: 10),
                  ...(_histories[id] ?? []).asMap().entries.map((e) {
                    final h = e.value;
                    final isCurrent = e.key == 0;
                    final hExpired =
                        h['expiry_date'] != null &&
                        DateTime.tryParse(
                              h['expiry_date'],
                            )?.isBefore(DateTime.now()) ==
                            true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? _kGreen.withAlpha(12)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isCurrent
                                ? _kGreen.withAlpha(60)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${isCurrent ? "Current" : "Archived"} · ${h['duration_label'] ?? '—'}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isCurrent ? _kGreen : Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              h['license_number'] ?? '—',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_fmt(h['start_date'])} → ${_fmt(h['expiry_date'])}',
                              style: TextStyle(
                                fontSize: 15,
                                color: hExpired && !isCurrent
                                    ? _kRed
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          );
        }),
        if (_loadingMore)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: _kOrange),
            ),
          ),
        if (!_loading && _total > 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                '${_members.length} members shown${_total > 0 ? " of $_total" : ""}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentSheet() => Container(
    color: Colors.black54,
    alignment: Alignment.bottomCenter,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Payment Verification',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedPayment = null),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...[
            'Applicant/${_selectedPayment['name']}',
            'Reference/${_selectedPayment['payment_ref'] ?? 'PENDING'}',
            'Company/${_selectedPayment['company'] ?? '—'}',
          ].map((entry) {
            final parts = entry.split('/');
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parts[0],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    parts[1],
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    _updateStatus(_selectedPayment['id'], 'active');
                    setState(() => _selectedPayment = null);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Verify & Approve'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    _updateStatus(_selectedPayment['id'], 'suspended');
                    setState(() => _selectedPayment = null);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kRed,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _infoTile(String label, String val, {bool mono = false}) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontFamily: mono ? 'monospace' : null,
          ),
        ),
      ],
    ),
  );

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
    ),
  );
}
