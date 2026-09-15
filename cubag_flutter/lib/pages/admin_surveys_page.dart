import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/custom_dropdown.dart';
import '../services/api_service.dart';
import '../components/fetch_error_view.dart';
import '../components/shimmer_loader.dart';
import 'package:cached_network_image/cached_network_image.dart';
part 'admin_surveys/admin_surveys_widgets.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10b981);
const _kRed = Color(0xFFef4444);
const _kPurple = Color(0xFF8b5cf6);
const _kBlue = Color(0xFF3b82f6);
const _kAmber = Color(0xFFf59e0b);
const _kIndigo = Color(0xFF6366F1);

class AdminSurveysPage extends StatefulWidget {
  const AdminSurveysPage({super.key});
  @override
  State<AdminSurveysPage> createState() => _State();
}

class _State extends State<AdminSurveysPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  List<dynamic> _activeSurveys = [];
  List<dynamic> _historySurveys = [];
  bool _loadingActive = true;
  bool _loadingHistory = true;
  bool _hasErrorActive = false;
  bool _hasErrorHistory = false;
  bool _submitting = false;
  bool _loadingMore = false;
  String _tab = 'active';
  dynamic _viewingResults;
  Map<String, dynamic>? _resultsData;
  bool _resultsLoading = false;
  Timer? _refreshTimer;
  int _countdown = 15;

  int _pageActive = 1;
  int _pageHistory = 1;
  int _totalActive = 0;
  int _totalHistory = 0;
  bool _hasMoreActive = true;
  bool _hasMoreHistory = true;

  final ScrollController _scrollController = ScrollController();

  // Create form
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _type = 'Survey', _method = 'Multiple Choice', _deadline = '';
  String _targetAudience = 'both';

  // Cover image
  String? _coverImageUrl;
  bool _uploadingCover = false;

  // Options: each entry has 'name' (String) and 'photo' (String?)
  List<Map<String, String?>> _options = [
    {'name': '', 'photo': null},
  ];
  // Track which option index is uploading its photo
  Set<int> _uploadingOptionIdx = {};

  @override
  void initState() {
    super.initState();
    _fetchActive();
    _fetchHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshTimer?.cancel();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_viewingResults != null) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_tab == 'active') {
        if (!_loadingActive && !_loadingMore && _hasMoreActive) {
          _fetchMore();
        }
      } else if (_tab == 'history') {
        if (!_loadingHistory && !_loadingMore && _hasMoreHistory) {
          _fetchMore();
        }
      }
    }
  }

  void _onTabChanged(String newTab) {
    if (_tab == newTab) return;
    setState(() => _tab = newTab);
    if (newTab == 'active' && _activeSurveys.isEmpty) {
      _fetchActive();
    } else if (newTab == 'history' && _historySurveys.isEmpty) {
      _fetchHistory();
    }
  }

  // ── Data ──────────────────────────────────────────────────────

  Future<void> _fetchActive({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _pageActive = 1;
        _hasMoreActive = true;
        _loadingActive = true;
        _activeSurveys = [];
      });
    } else {
      if (_activeSurveys.isEmpty) setState(() => _loadingActive = true);
    }

    await _api.fetchDataWithCache(
      'surveys/admin/all?page=$_pageActive&per_page=20&status=active',
      (data, isCached, {bool hasError = false}) {
        if (!mounted) return;
        if (hasError && _activeSurveys.isEmpty) {
          setState(() {
            _loadingActive = false;
            _hasErrorActive = true;
          });
          return;
        }
        if (data == null) {
          setState(() => _loadingActive = false);
          return;
        }
        setState(() {
          final raw = data is Map
              ? (data['data'] ?? data['items'] ?? data)
              : data;
          _activeSurveys = raw is List ? raw : [];
          if (data is Map && data.containsKey('total')) {
            _totalActive = data['total'];
            _hasMoreActive = _activeSurveys.length < _totalActive;
          } else {
            _hasMoreActive = false;
          }
          _loadingActive = false;
          _hasErrorActive = false;
        });
      },
    );
  }

  Future<void> _fetchHistory({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _pageHistory = 1;
        _hasMoreHistory = true;
        _loadingHistory = true;
        _historySurveys = [];
      });
    } else {
      if (_historySurveys.isEmpty) setState(() => _loadingHistory = true);
    }

    await _api.fetchDataWithCache(
      'surveys/admin/all?page=$_pageHistory&per_page=20&status=history',
      (data, isCached, {bool hasError = false}) {
        if (!mounted) return;
        if (hasError && _historySurveys.isEmpty) {
          setState(() {
            _loadingHistory = false;
            _hasErrorHistory = true;
          });
          return;
        }
        if (data == null) {
          setState(() => _loadingHistory = false);
          return;
        }
        setState(() {
          final raw = data is Map
              ? (data['data'] ?? data['items'] ?? data)
              : data;
          _historySurveys = raw is List ? raw : [];
          if (data is Map && data.containsKey('total')) {
            _totalHistory = data['total'];
            _hasMoreHistory = _historySurveys.length < _totalHistory;
          } else {
            _hasMoreHistory = false;
          }
          _loadingHistory = false;
          _hasErrorHistory = false;
        });
      },
    );
  }

  Future<void> _fetch({bool refresh = false}) async {
    if (!mounted) return;
    if (_tab == 'active') {
      await _fetchActive(refresh: refresh);
      if (_historySurveys.isEmpty || refresh) {
        _fetchHistory(refresh: refresh);
      }
    } else if (_tab == 'history') {
      await _fetchHistory(refresh: refresh);
      if (_activeSurveys.isEmpty || refresh) {
        _fetchActive(refresh: refresh);
      }
    } else {
      _fetchActive(refresh: refresh);
      _fetchHistory(refresh: refresh);
    }
  }

  Future<void> _fetchMore() async {
    final targetTab = _tab;
    if (targetTab == 'active') {
      setState(() => _loadingMore = true);
      _pageActive++;
      try {
        final data = await _api.fetchData(
          'surveys/admin/all?page=$_pageActive&per_page=20&status=active',
        );
        if (mounted) {
          final raw = data is Map
              ? (data['data'] ?? data['items'] ?? data)
              : data;
          final newItems = raw is List ? raw : [];
          setState(() {
            _activeSurveys.addAll(newItems);
            if (data is Map && data.containsKey('total')) {
              _hasMoreActive = _activeSurveys.length < data['total'];
            } else {
              _hasMoreActive = newItems.isNotEmpty;
            }
          });
        }
      } catch (_) {
        _pageActive--;
      }
      if (mounted) setState(() => _loadingMore = false);
    } else if (targetTab == 'history') {
      setState(() => _loadingMore = true);
      _pageHistory++;
      try {
        final data = await _api.fetchData(
          'surveys/admin/all?page=$_pageHistory&per_page=20&status=history',
        );
        if (mounted) {
          final raw = data is Map
              ? (data['data'] ?? data['items'] ?? data)
              : data;
          final newItems = raw is List ? raw : [];
          setState(() {
            _historySurveys.addAll(newItems);
            if (data is Map && data.containsKey('total')) {
              _hasMoreHistory = _historySurveys.length < data['total'];
            } else {
              _hasMoreHistory = newItems.isNotEmpty;
            }
          });
        }
      } catch (_) {
        _pageHistory--;
      }
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadResults(dynamic survey) async {
    setState(() {
      _viewingResults = survey;
      _resultsData = null;
      _resultsLoading = true;
    });
    _startAutoRefresh(survey['id']);
    await _refreshResults(survey['id']);
  }

  Future<void> _refreshResults(int surveyId) async {
    final data = await _api.fetchData('surveys/$surveyId/participation');
    if (mounted) {
      setState(() {
        _resultsData = data is Map ? Map<String, dynamic>.from(data) : null;
        _resultsLoading = false;
        _countdown = 15;
      });
    }
  }

  void _startAutoRefresh(int surveyId) {
    _refreshTimer?.cancel();
    _countdown = 15;
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        _countdown = 15;
        _refreshResults(surveyId);
      }
    });
  }

  void _closeResults() {
    _refreshTimer?.cancel();
    setState(() {
      _viewingResults = null;
      _resultsData = null;
    });
  }

  // ── Image Upload ───────────────────────────────────────────────

  Future<String?> _uploadImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.bytes == null && file.path == null) return null;

    late MultipartFile mpFile;
    if (file.bytes != null) {
      final exactBytes = Uint8List.fromList(file.bytes!);
      mpFile = MultipartFile.fromBytes(exactBytes, filename: file.name);
    } else {
      mpFile = await MultipartFile.fromFile(file.path!, filename: file.name);
    }

    try {
      final res = await _api.upload(
        '/uploads/image',
        FormData.fromMap({'image': mpFile}),
      );
      if (res.statusCode == 201 && res.data['url'] != null) {
        return res.data['url'].toString();
      }
      _showSnack(
        'Upload failed: ${res.data['message'] ?? 'Unknown error'}',
        isError: true,
      );
      return null;
    } catch (e) {
      _showSnack('Upload error: $e', isError: true);
      return null;
    }
  }

  Future<void> _pickCoverImage() async {
    setState(() => _uploadingCover = true);
    final url = await _uploadImage();
    setState(() {
      _coverImageUrl = url ?? _coverImageUrl;
      _uploadingCover = false;
    });
    if (url != null) _showSnack('Cover image uploaded ✓');
  }

  Future<void> _pickOptionPhoto(int idx) async {
    setState(() => _uploadingOptionIdx = {..._uploadingOptionIdx, idx});
    final url = await _uploadImage();
    if (url != null) {
      setState(() {
        _options[idx] = {..._options[idx], 'photo': url};
      });
    }
    setState(() {
      final s = Set<int>.from(_uploadingOptionIdx);
      s.remove(idx);
      _uploadingOptionIdx = s;
    });
    if (url != null) _showSnack('Candidate photo uploaded ✓');
  }

  // ── CRUD ───────────────────────────────────────────────────────

  Future<void> _create() async {
    if (_titleCtrl.text.isEmpty ||
        _descCtrl.text.isEmpty ||
        _deadline.isEmpty) {
      _showSnack('Please fill in all required fields.', isError: true);
      return;
    }
    setState(() => _submitting = true);
    final res = await _api.post(
      '/surveys',
      data: {
        'title': _titleCtrl.text,
        'description': _descCtrl.text,
        'type': _type,
        'method': _method,
        'target_audience': _targetAudience,
        'deadline': _deadline,
        'cover_image': _coverImageUrl,
        'options': _options
            .where((o) => (o['name'] ?? '').isNotEmpty)
            .map((o) => {'name': o['name'], 'photo': o['photo']})
            .toList(),
      },
    );
    if (res.statusCode == 201) {
      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _submitting = false;
        _options = [
          {'name': '', 'photo': null},
        ];
        _deadline = '';
        _targetAudience = 'both';
        _coverImageUrl = null;
        _tab = 'active';
      });
      _showSnack('Poll published successfully!');
      await _fetch(refresh: true);
    } else {
      setState(() => _submitting = false);
      _showSnack('Failed to create poll.', isError: true);
    }
  }

  Future<void> _delete(int id) async {
    await _api.deleteData('surveys/$id');
    if (_viewingResults != null && _viewingResults['id'] == id) _closeResults();
    await _fetch(refresh: true);
  }

  Future<void> _toggleActive(dynamic survey) async {
    final res = await _api.put('/surveys/${survey['id']}/toggle-active');
    if (res.statusCode == 200) {
      _showSnack(res.data['message'] ?? 'Status updated');
      await _fetch(refresh: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isError ? _kRed : _kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Color _typeColor(String? t) {
    switch (t?.toLowerCase()) {
      case 'election':
        return _kPurple;
      case 'poll':
        return _kBlue;
      default:
        return _kOrange;
    }
  }

  IconData _typeIcon(String? t) {
    switch (t?.toLowerCase()) {
      case 'election':
        return Icons.how_to_vote_outlined;
      case 'poll':
        return Icons.bar_chart_outlined;
      default:
        return Icons.assignment_outlined;
    }
  }

  // ── Build ────────────────────────────────────────────────────

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

    if (_viewingResults != null) {
      return AppLayout(
        title: 'Live Results',
        child: _buildResultsView(
          isDark,
          cardBg,
          borderColor,
          textColor,
          subTextColor,
        ),
      );
    }
    return AppLayout(
      title: 'Surveys & Elections',
      scrollable: false,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminHeader(
              title: 'Surveys & Association Elections Hub',
              subtitle:
                  'Launch executive elections, governance referendums, member satisfaction surveys, and inspect encrypted real-time balloting results.',
              actions: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                    side: BorderSide(color: borderColor, width: 1.2),
                    backgroundColor: cardBg,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _fetch(refresh: true),
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: _kOrange),
                  label: Text('Refresh', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const SizedBox(width: 8),
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
                  onPressed: () {
                    if (_tab == 'create') {
                      _onTabChanged('active');
                    } else {
                      _onTabChanged('create');
                    }
                  },
                  icon: Icon(
                    _tab == 'create'
                        ? Icons.ballot_outlined
                        : Icons.add_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _tab == 'create'
                        ? 'View Active Polls'
                        : 'New Poll / Ballot',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── KPI METRICS BANNER ───────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                final activeCount = _totalActive > 0 ? _totalActive : _activeSurveys.length;
                final historyCount = _totalHistory > 0 ? _totalHistory : _historySurveys.length;
                final totalCount = activeCount + historyCount;

                return isWide
                    ? Row(
                        children: [
                          Expanded(child: _buildMetricTile('Active Ballots', '$activeCount', 'Currently open for voting', Icons.how_to_vote_rounded, _kGreen, cardBg, borderColor, textColor, subTextColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricTile('Archived History', '$historyCount', 'Closed surveys & ballots', Icons.history_edu_rounded, _kIndigo, cardBg, borderColor, textColor, subTextColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricTile('Total Polls Created', '$totalCount', 'Association-wide total', Icons.bar_chart_rounded, _kOrange, cardBg, borderColor, textColor, subTextColor)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricTile('Encrypted Audit', '100% Secure', 'Anonymized cryptographic hash', Icons.verified_user_rounded, _kPurple, cardBg, borderColor, textColor, subTextColor)),
                        ],
                      )
                    : Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildMetricTile('Active Ballots', '$activeCount', 'Currently open', Icons.how_to_vote_rounded, _kGreen, cardBg, borderColor, textColor, subTextColor)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildMetricTile('Archived History', '$historyCount', 'Closed polls', Icons.history_edu_rounded, _kIndigo, cardBg, borderColor, textColor, subTextColor)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _buildMetricTile('Total Polls', '$totalCount', 'Association-wide', Icons.bar_chart_rounded, _kOrange, cardBg, borderColor, textColor, subTextColor)),
                              const SizedBox(width: 10),
                              Expanded(child: _buildMetricTile('Audit Status', 'Verified', 'Cryptographic', Icons.verified_user_rounded, _kPurple, cardBg, borderColor, textColor, subTextColor)),
                            ],
                          ),
                        ],
                      );
              },
            ),
            const SizedBox(height: 16),

            // ── MODERN SEGMENTED TABS WITH COUNTERS ───────────────────────────
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  _buildTabPill('active', 'Active (${_totalActive > 0 ? _totalActive : _activeSurveys.length})', Icons.play_circle_outline_rounded, _kGreen, textColor, subTextColor),
                  const SizedBox(width: 6),
                  _buildTabPill('history', 'History (${_totalHistory > 0 ? _totalHistory : _historySurveys.length})', Icons.archive_outlined, _kIndigo, textColor, subTextColor),
                  const SizedBox(width: 6),
                  _buildTabPill('create', '+ New Poll', Icons.add_chart_rounded, _kOrange, textColor, subTextColor),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_tab == 'create')
              _buildCreateForm(
                isDark,
                cardBg,
                borderColor,
                textColor,
                subTextColor,
                inputBg,
              ),
            if (_tab != 'create')
              _buildSurveyList(
                isDark,
                cardBg,
                borderColor,
                textColor,
                subTextColor,
              ),
          ],
        ),
      ),
    );
  }

  // ── Survey Card List ─────────────────────────────────────────

  Widget _buildSurveyList(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final surveys = _tab == 'active' ? _activeSurveys : _historySurveys;
    final loading = _tab == 'active' ? _loadingActive : _loadingHistory;
    final hasError = _tab == 'active' ? _hasErrorActive : _hasErrorHistory;
    final total = _tab == 'active' ? _totalActive : _totalHistory;

    return LayoutBuilder(
      builder: (context, constraints) {
        double cardWidth = constraints.maxWidth;
        if (constraints.maxWidth > 1200) {
          cardWidth = (constraints.maxWidth - 48) / 4;
        } else if (constraints.maxWidth > 800) {
          cardWidth = (constraints.maxWidth - 32) / 3;
        } else if (constraints.maxWidth > 600) {
          cardWidth = (constraints.maxWidth - 16) / 2;
        }

        if (loading) {
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: List.generate(
              8,
              (_) => Container(
                width: cardWidth,
                height: 240,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: const ShimmerGridCard(),
              ),
            ),
          );
        }

        if (hasError && surveys.isEmpty) {
          return FetchErrorView(onRetry: () => _fetch(refresh: true));
        }
        if (surveys.isEmpty) {
          return _emptyState(cardBg, borderColor, subTextColor);
        }

        return Column(
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: surveys
                  .map(
                    (s) => SizedBox(
                      width: cardWidth,
                      child: _surveyCard(
                        s,
                        isDark,
                        cardBg,
                        borderColor,
                        textColor,
                        subTextColor,
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: _kOrange),
              ),
            if (!loading && total > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '${surveys.length} of $total polls shown',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: subTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _emptyState(Color cardBg, Color borderColor, Color subTextColor) =>
      Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: subTextColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.ballot_outlined, size: 40, color: subTextColor),
            ),
            const SizedBox(height: 16),
            Text(
              'No polls found',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: subTextColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a new poll using the "New Poll" tab.',
              style: GoogleFonts.outfit(fontSize: 16, color: subTextColor),
            ),
          ],
        ),
      );

  Widget _targetBadge(String? target, bool isDark) {
    final t = (target ?? 'both').toLowerCase();
    late final Color color;
    late final IconData icon;
    late final String label;
    if (t == 'members') {
      color = _kPurple;
      icon = Icons.lock_outline_rounded;
      label = 'Members Only';
    } else if (t == 'guests') {
      color = _kOrange;
      icon = Icons.public_rounded;
      label = 'Public Guests';
    } else {
      color = const Color(0xFF0284c7);
      icon = Icons.language_rounded;
      label = 'Both Parties';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _surveyCard(
    dynamic s,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final type = s['type']?.toString() ?? 'Survey';
    final color = _typeColor(type);
    final icon = _typeIcon(type);
    final isActive = s['active'] != false;
    final deadline = s['deadline']?.toString();
    final isExpired = deadline != null && deadline.compareTo(_today()) < 0;
    final statusLabel = !isActive
        ? 'Closed'
        : isExpired
        ? 'Expired'
        : 'Active';
    final statusColor = !isActive
        ? _kRed
        : isExpired
        ? _kAmber
        : _kGreen;
    final coverImage = s['cover_image']?.toString();
    final targetAudience = s['target_audience']?.toString() ?? 'both';

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverImage != null && coverImage.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
              child: CachedNetworkImage(
                imageUrl: coverImage,
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: coverImage != null && coverImage.isNotEmpty
                  ? BorderRadius.zero
                  : const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(
                bottom: BorderSide(color: color.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 8),
                Text(
                  type.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                _targetBadge(targetAudience, isDark),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s['title'] ?? '',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                if (s['description'] != null)
                  Text(
                    s['description'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: subTextColor,
                      height: 1.4,
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: subTextColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      deadline != null ? 'Deadline: $deadline' : 'No deadline',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: subTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _loadResults(s),
                        icon: const Icon(Icons.bar_chart_rounded, size: 16),
                        label: Text(
                          'Results',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _iconBtn(
                      icon: isActive
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                      color: isActive ? _kAmber : _kGreen,
                      tooltip: isActive ? 'Close Poll' : 'Reopen Poll',
                      onTap: () => _toggleActive(s),
                    ),
                    const SizedBox(width: 8),
                    _iconBtn(
                      icon: Icons.delete_outline_rounded,
                      color: _kRed,
                      tooltip: 'Delete',
                      onTap: () => _confirmDelete(
                        s,
                        isDark,
                        cardBg,
                        borderColor,
                        textColor,
                        subTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    ),
  );

  void _confirmDelete(
    dynamic s,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        title: Text(
          'Delete Poll',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        content: Text(
          'Are you sure you want to permanently delete "${s['title']}"? All responses will also be deleted.',
          style: GoogleFonts.outfit(color: subTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(
                color: subTextColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _delete(s['id']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ── Live Results View ────────────────────────────────────────

  Widget _buildResultsView(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final s = _viewingResults;
    final type = s['type']?.toString() ?? 'Survey';
    final color = _typeColor(type);
    final targetAudience = s['target_audience']?.toString() ?? 'both';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: _closeResults,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: subTextColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 18, color: textColor),
                    const SizedBox(width: 8),
                    Text(
                      'Back',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s['title'] ?? '',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _targetBadge(targetAudience, isDark),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$type • Deadline: ${s['deadline'] ?? 'None'}',
                    style: GoogleFonts.outfit(
                      color: subTextColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              _resultsLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: color,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(Icons.sync_rounded, size: 16, color: color),
              const SizedBox(width: 10),
              Text(
                _resultsLoading
                    ? 'Refreshing...'
                    : 'Auto-refresh in ${_countdown}s',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() => _resultsLoading = true);
                  _refreshResults(s['id']);
                },
                child: Text(
                  'Refresh Now',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_resultsLoading && _resultsData == null)
          Column(
            children: List.generate(
              3,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: ShimmerListTile(),
              ),
            ),
          )
        else if (_resultsData == null)
          Center(
            child: Text(
              'Could not load results.',
              style: GoogleFonts.outfit(color: subTextColor),
            ),
          )
        else
          _buildResultsContent(
            color,
            isDark,
            cardBg,
            borderColor,
            textColor,
            subTextColor,
          ),
      ],
    );
  }

  Widget _buildResultsContent(
    Color color,
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    final responded = _resultsData!['responded'] as List? ?? [];
    final notResponded = _resultsData!['not_responded'] as List? ?? [];
    final guestResponses = _resultsData!['guest_responses'] as List? ?? [];
    final memberVotes =
        _resultsData!['member_votes_count'] as int? ?? responded.length;
    final guestVotes =
        _resultsData!['guest_votes_count'] as int? ?? guestResponses.length;
    final totalVotes =
        _resultsData!['total_votes'] as int? ?? (memberVotes + guestVotes);
    final rate = (_resultsData!['response_rate'] as num?)?.toDouble() ?? 0.0;
    final tallies = _resultsData!['tallies'] as Map? ?? {};
    final avgStars =
        (_resultsData!['average_stars'] as num?)?.toDouble() ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _kpiCard(
              'Total Votes',
              '$totalVotes',
              Icons.how_to_vote_rounded,
              const Color(0xFF0284c7),
              cardBg,
              borderColor,
              isDark,
            ),
            const SizedBox(width: 12),
            _kpiCard(
              'Member Votes',
              '$memberVotes',
              Icons.verified_user_rounded,
              _kGreen,
              cardBg,
              borderColor,
              isDark,
            ),
            const SizedBox(width: 12),
            _kpiCard(
              'Guest Votes',
              '$guestVotes',
              Icons.public_rounded,
              _kOrange,
              cardBg,
              borderColor,
              isDark,
            ),
            const SizedBox(width: 12),
            _kpiCard(
              'Member Rate',
              '${rate.toStringAsFixed(0)}%',
              Icons.pie_chart_rounded,
              _kPurple,
              cardBg,
              borderColor,
              isDark,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.02),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CustomPaint(
                      painter: _RingPainter(
                        totalVotes > 0 ? (memberVotes / totalVotes) : 0.0,
                        color,
                        borderColor,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$totalVotes',
                              style: GoogleFonts.outfit(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: color,
                              ),
                            ),
                            Text(
                              'total votes',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: subTextColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Overall Participation',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.1 : 0.02,
                      ),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: tallies.isNotEmpty
                    ? _buildTallyBars(
                        tallies,
                        totalVotes,
                        color,
                        textColor,
                        subTextColor,
                        isDark,
                      )
                    : avgStars > 0
                    ? _buildStarResult(avgStars, textColor, subTextColor)
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(
                                Icons.pending_actions_rounded,
                                size: 40,
                                color: subTextColor.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No votes recorded yet',
                                style: GoogleFonts.outfit(
                                  color: subTextColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _memberList(
                'Responded Members',
                responded,
                _kGreen,
                cardBg,
                borderColor,
                textColor,
                subTextColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _guestList(
                'Public Guest Votes',
                guestResponses,
                _kOrange,
                cardBg,
                borderColor,
                textColor,
                subTextColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _memberList(
                'Pending Members',
                notResponded,
                _kAmber,
                cardBg,
                borderColor,
                textColor,
                subTextColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTallyBars(
    Map tallies,
    int total,
    Color color,
    Color textColor,
    Color subTextColor,
    bool isDark,
  ) {
    final maxVotes = tallies.values.fold<int>(
      0,
      (m, v) => math.max(m, (v as num).toInt()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Voting Results',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: textColor,
          ),
        ),
        const SizedBox(height: 16),
        ...tallies.entries.map((e) {
          final votes = (e.value as num).toInt();
          final pct = total > 0 ? (votes / total).clamp(0.0, 1.0) : 0.0;
          final barPct = maxVotes > 0
              ? (votes / maxVotes).clamp(0.0, 1.0)
              : 0.0;
          final isLeader = votes == maxVotes && votes > 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isLeader)
                      const Icon(
                        Icons.emoji_events_rounded,
                        size: 16,
                        color: _kAmber,
                      ),
                    if (isLeader) const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        e.key.toString(),
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isLeader ? color : textColor,
                        ),
                      ),
                    ),
                    Text(
                      '$votes votes',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: subTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${(pct * 100).toStringAsFixed(1)}%',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: barPct.toDouble(),
                    color: isLeader ? color : color.withValues(alpha: 0.4),
                    backgroundColor: subTextColor.withValues(alpha: 0.1),
                    minHeight: 10,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStarResult(double avg, Color textColor, Color subTextColor) =>
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Average Rating',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: textColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            avg.toStringAsFixed(1),
            style: GoogleFonts.outfit(
              fontSize: 58,
              fontWeight: FontWeight.w900,
              color: _kAmber,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < avg;
              final half = !filled && i < avg.ceil() && avg % 1 >= 0.5;
              return Icon(
                filled
                    ? Icons.star_rounded
                    : half
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
                color: _kAmber,
                size: 32,
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'out of 5.0',
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: subTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );

  Widget _kpiCard(
    String label,
    String value,
    IconData icon,
    Color color,
    Color cardBg,
    Color borderColor,
    bool isDark,
  ) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.02),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color.withValues(alpha: 0.8),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _memberList(
    String title,
    List members,
    Color color,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) => Container(
    constraints: const BoxConstraints(maxHeight: 240),
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10),
      ],
    ),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(
              bottom: BorderSide(color: color.withValues(alpha: 0.2)),
            ),
          ),
          child: Row(
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${members.length}',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: members.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'None',
                    style: GoogleFonts.outfit(
                      color: subTextColor,
                      fontSize: 16,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: members.length,
                  separatorBuilder: (ctx, i) => Divider(
                    height: 1,
                    color: borderColor.withValues(alpha: 0.5),
                  ),
                  itemBuilder: (_, i) {
                    final m = members[i];
                    final vote = m['vote']?.toString();
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Text(
                          (m['name']?.toString() ?? '?').substring(0, 1),
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ),
                      title: Text(
                        m['name']?.toString() ?? '',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        m['company']?.toString() ??
                            m['email']?.toString() ??
                            '',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: subTextColor,
                        ),
                      ),
                      trailing: vote != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                vote,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Widget _guestList(
    String title,
    List guests,
    Color color,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) => Container(
    constraints: const BoxConstraints(maxHeight: 240),
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10),
      ],
    ),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(
              bottom: BorderSide(color: color.withValues(alpha: 0.2)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.public_rounded, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${guests.length}',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: guests.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No guest responses yet',
                    style: GoogleFonts.outfit(
                      color: subTextColor,
                      fontSize: 16,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: guests.length,
                  separatorBuilder: (ctx, i) => Divider(
                    height: 1,
                    color: borderColor.withValues(alpha: 0.5),
                  ),
                  itemBuilder: (_, i) {
                    final g = guests[i];
                    final vote = g['vote']?.toString();
                    final submitted = g['submitted_at']?.toString() ?? '';
                    final name = g['name']?.toString() ?? 'Public Guest';
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Icon(
                          Icons.person_outline_rounded,
                          size: 16,
                          color: color,
                        ),
                      ),
                      title: Text(
                        name,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        g['email'] != null && g['email'] != 'Anonymous'
                            ? '${g['email']} • $submitted'
                            : submitted,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: subTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: vote != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                vote,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            )
                          : null,
                    );
                  },
                ),
        ),
      ],
    ),
  );

  // ── Create Form ──────────────────────────────────────────────

  Widget _buildCreateForm(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
    Color inputBg,
  ) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.1 : 0.02),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.add_chart_rounded,
                color: _kOrange,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Create New Poll / Election',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Cover / Banner Image ──────────────────────────────
        _labeledWidget(
          'Cover Image (optional)',
          _buildCoverImagePicker(borderColor, subTextColor),
          subTextColor,
        ),
        const SizedBox(height: 20),

        _field(
          'Poll Title *',
          _titleCtrl,
          hint: 'e.g. 2026 Board of Directors Election',
          textColor: textColor,
          subTextColor: subTextColor,
          borderColor: borderColor,
          inputBg: inputBg,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _labeledWidget(
                'Poll Type',
                CustomDropdown<String>(
                  value: _type,
                  items: const [
                    DropdownItem(value: 'Survey', label: 'Survey'),
                    DropdownItem(value: 'Election', label: 'Election'),
                    DropdownItem(value: 'Poll', label: 'Quick Poll'),
                  ],
                  onChanged: (v) => setState(() => _type = v),
                ),
                subTextColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _labeledWidget(
                'Response Method',
                CustomDropdown<String>(
                  value: _method,
                  items: const [
                    DropdownItem(
                      value: 'Multiple Choice',
                      label: 'Multiple Choice',
                    ),
                    DropdownItem(value: 'Yes/No', label: 'Yes / No'),
                    DropdownItem(value: 'Star Rating', label: 'Star Rating'),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _method = v;
                      if (v == 'Yes/No') {
                        _options = [
                          {'name': 'Yes', 'photo': null},
                          {'name': 'No', 'photo': null},
                        ];
                      } else if (v == 'Star Rating') {
                        _options = [];
                      } else {
                        _options = [
                          {'name': '', 'photo': null},
                        ];
                      }
                    });
                  },
                ),
                subTextColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _labeledWidget(
          'Target Audience / Participants *',
          CustomDropdown<String>(
            value: _targetAudience,
            items: const [
              DropdownItem(
                value: 'both',
                label: '🌐 Both Parties (Members & General Public Guests)',
              ),
              DropdownItem(
                value: 'members',
                label: '🔒 Members Only (Member Portal Only)',
              ),
              DropdownItem(
                value: 'guests',
                label: '👥 General Public / Guests Only (Homepage Only)',
              ),
            ],
            onChanged: (v) => setState(() => _targetAudience = v),
          ),
          subTextColor,
        ),
        const SizedBox(height: 16),
        _field(
          'Description *',
          _descCtrl,
          hint: 'Provide instructions or context for voters...',
          maxLines: 3,
          textColor: textColor,
          subTextColor: subTextColor,
          borderColor: borderColor,
          inputBg: inputBg,
        ),
        const SizedBox(height: 16),
        _labeledWidget(
          'Deadline *',
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime(2099),
              );
              if (picked != null) {
                setState(
                  () => _deadline =
                      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: inputBg,
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: subTextColor,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _deadline.isEmpty ? 'Pick a deadline date' : _deadline,
                    style: GoogleFonts.outfit(
                      color: _deadline.isEmpty ? subTextColor : textColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          subTextColor,
        ),

        if (_method == 'Multiple Choice') ...[
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Options / Candidates *',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: textColor,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'Add Option',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () =>
                    setState(() => _options.add({'name': '', 'photo': null})),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._options.asMap().entries.map(
            (e) => _buildOptionRow(
              e.key,
              e.value,
              textColor,
              subTextColor,
              borderColor,
              inputBg,
            ),
          ),
        ],

        if (_method == 'Yes/No') ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBlue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 20, color: _kBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Members will vote with a "Yes" or "No" button.',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: _kBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_method == 'Star Rating') ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kAmber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kAmber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, size: 20, color: _kAmber),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Members will submit a rating from 1 to 5 stars.',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: _kAmber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _create,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.publish_rounded, size: 20),
            label: Text(
              _submitting ? 'Publishing...' : 'Publish Poll',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Cover Image Picker Widget ─────────────────────────────────

  Widget _buildCoverImagePicker(Color borderColor, Color subTextColor) {
    return GestureDetector(
      onTap: _uploadingCover ? null : _pickCoverImage,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: subTextColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _coverImageUrl != null
                ? _kGreen.withValues(alpha: 0.5)
                : borderColor,
            width: 2,
          ),
          image: _coverImageUrl != null
              ? DecorationImage(
                  image: CachedNetworkImageProvider(_coverImageUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: _coverImageUrl != null
            ? Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to change',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: _kGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              )
            : _uploadingCover
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: _kOrange, strokeWidth: 2),
                    SizedBox(height: 12),
                    Text(
                      'Uploading...',
                      style: TextStyle(
                        color: _kOrange,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _kOrange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_rounded,
                      color: _kOrange,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Upload Cover Image',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: subTextColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PNG, JPG, WEBP — up to 10 MB',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: subTextColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Option Row with Photo Upload ─────────────────────────────

  Widget _buildOptionRow(
    int idx,
    Map<String, String?> opt,
    Color textColor,
    Color subTextColor,
    Color borderColor,
    Color inputBg,
  ) {
    final photoUrl = opt['photo'];
    final isUploading = _uploadingOptionIdx.contains(idx);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kOrange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${idx + 1}',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: _kOrange,
              ),
            ),
          ),
          const SizedBox(width: 12),

          GestureDetector(
            onTap: isUploading ? null : () => _pickOptionPhoto(idx),
            child: Stack(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: photoUrl != null ? null : inputBg,
                    border: Border.all(
                      color: photoUrl != null
                          ? _kGreen.withValues(alpha: 0.5)
                          : borderColor,
                      width: 2,
                    ),
                    image: photoUrl != null
                        ? DecorationImage(
                            image: NetworkImage(photoUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: isUploading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kOrange,
                          ),
                        )
                      : photoUrl == null
                      ? Icon(
                          Icons.add_a_photo_rounded,
                          color: subTextColor,
                          size: 22,
                        )
                      : null,
                ),
                if (photoUrl != null && !isUploading)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: _kOrange,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: TextFormField(
              initialValue: opt['name'],
              style: GoogleFonts.outfit(color: textColor, fontSize: 16),
              decoration: _deco(
                hint: idx == 0 && _type == 'Election'
                    ? 'Candidate name...'
                    : 'Option label...',
                subTextColor: subTextColor,
                borderColor: borderColor,
                inputBg: inputBg,
              ),
              onChanged: (v) =>
                  setState(() => _options[idx] = {..._options[idx], 'name': v}),
            ),
          ),

          if (_options.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: _kRed,
                  size: 22,
                ),
                onPressed: () => setState(() => _options.removeAt(idx)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _labeledWidget(String label, Widget child, Color subTextColor) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: subTextColor,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      );

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    int maxLines = 1,
    required Color textColor,
    required Color subTextColor,
    required Color borderColor,
    required Color inputBg,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: subTextColor,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: GoogleFonts.outfit(color: textColor, fontSize: 14),
        decoration: _deco(
          hint: hint,
          subTextColor: subTextColor,
          borderColor: borderColor,
          inputBg: inputBg,
        ),
      ),
    ],
  );

  InputDecoration _deco({
    String? hint,
    required Color subTextColor,
    required Color borderColor,
    required Color inputBg,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.outfit(fontSize: 16, color: subTextColor),
    filled: true,
    fillColor: inputBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: borderColor, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kOrange, width: 2),
    ),
  );

  Widget _buildMetricTile(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: textColor.withAlpha(200),
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: subTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(
    String id,
    String label,
    IconData icon,
    Color activeColor,
    Color textColor,
    Color subTextColor,
  ) {
    final isActive = _tab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabChanged(id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isActive ? Colors.white : subTextColor,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: isActive ? Colors.white : textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Ring Painter ─────────────────────────────────────────────────
