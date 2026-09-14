import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;
import '../components/app_logo.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../services/socket_service.dart';
import '../utils/app_colors.dart';
import '../components/cors_image_widget.dart';

// ── CUBAG Dynamic Theme System ───────────────────────────────────────────────
bool get _globalIsDark => ThemeService.instance.isDark;
Color get _kBg => _globalIsDark
    ? const Color(0xFF1A0F0A)
    : const Color(0xFFFFFFFF); // deep espresso chocolate
Color get _kCream => _globalIsDark
    ? const Color(0xFF281710)
    : const Color(0xFFF8F4F0); // warm velvet chocolate
Color get _kCardBg => _globalIsDark
    ? const Color(0xFF281710)
    : Colors.white; // chocolate cards & surfaces
Color get _kBrown => _globalIsDark
    ? const Color(0xFFFF5000)
    : const Color(0xFF6B3E26); // shining caramel gold
Color get _kAccent => const Color(0xFFFF5000); // CTA, active states ONLY
Color get _kText => _globalIsDark
    ? const Color(0xFFFFF8F3)
    : const Color(0xFF2B211D); // warm ivory cream text
Color get _kMuted => _globalIsDark
    ? const Color(0xFFC8ADA0)
    : const Color(0xFF6F625B); // soft cocoa tan muted
Color get _kBorder => _globalIsDark
    ? const Color(0xFF4D2D20)
    : const Color(0xFFE8DED6); // warm bronze borders
Color get _kFooter => _globalIsDark
    ? const Color(0xFF120A06)
    : const Color(0xFF2B211D); // deepest espresso footer

TextStyle _outfit({
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'Outfit',
    fontFamilyFallback: const ['Inter', 'sans-serif'],
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
  );
}

TextStyle _inter({
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const ['sans-serif'],
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
  );
}

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();

  // Section scroll keys
  final GlobalKey _heroKey = GlobalKey();
  final GlobalKey _servicesKey = GlobalKey();
  final GlobalKey _updatesKey = GlobalKey();
  final GlobalKey _directoryKey = GlobalKey();
  final GlobalKey _eventsKey = GlobalKey();
  final GlobalKey _trainingKey = GlobalKey();
  final GlobalKey _complaintsKey = GlobalKey();
  final GlobalKey _surveysKey = GlobalKey();
  final GlobalKey _galleryKey = GlobalKey();
  final GlobalKey _contactKey = GlobalKey();

  final TextEditingController _homeTrackCtrl = TextEditingController();
  bool _homeTracking = false;
  Map<String, dynamic>? _homeTrackResult;
  String? _homeTrackError;

  bool _scrolled = false;
  bool _mobileMenuOpen = false;

  // Member directory
  final TextEditingController _dirSearchCtrl = TextEditingController();
  List<dynamic> _directoryMembers = [];

  // Real-time News & Port Bulletins
  List<dynamic> _newsArticles = [];
  bool _loadingNews = false;
  List<dynamic> _portBulletins = [];
  bool _loadingBulletins = false;

  // Real-time Events & Meetings
  List<dynamic> _eventsList = [];
  List<dynamic> _meetingsList = [];
  bool _loadingEvents = false;

  // Real-time CTI Short Courses
  List<dynamic> _coursesList = [];
  bool _loadingCourses = false;

  // Real-time Public Surveys & Polls
  List<dynamic> _publicSurveys = [];
  bool _loadingSurveys = false;
  int _activeSurveyIdx = 0;
  final Map<int, String> _selectedOptionMap = {};
  final Set<int> _votedSurveyIds = {};
  final Map<int, bool> _submittingSurvey = {};
  String _guestId = '';

  // Real-time Gallery
  final ScrollController _galleryScrollCtrl = ScrollController();
  List<dynamic> _galleryList = [];
  bool _loadingGallery = false;
  Timer? _galleryAutoTimer;
  Timer? _backgroundSyncTimer;

  // Ports count
  int _portsCount = 6;

  // Segmented tab state
  int _activeUpdatesTab = 0; // 0 = Port News, 1 = Industry News
  int _activeEventsTab = 0; // 0 = Events,    1 = Meetings

  // Mobile footer accordion
  bool _footerAboutExpanded = false;
  bool _footerLinksExpanded = false;
  bool _footerContactExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_scrollListener);
    _initGuestAndVotes();
    _fetchAllLandingData();

    // Attach real-time sync listeners
    SocketService().dataUpdateNotifier.addListener(_onGlobalDataUpdate);
    SocketService().on('news_updated', _onRealtimeNews);
    SocketService().on('bulletins_updated', _onRealtimeBulletins);
    SocketService().on('courses_updated', _onRealtimeCourses);
    SocketService().on('events_updated', _onRealtimeEvents);
    SocketService().on('gallery_updated', _onRealtimeGallery);
    SocketService().on('surveys_updated', _onRealtimeSurveys);

    // Silent background auto-sync polling every 20 seconds
    _backgroundSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) {
        _fetchAllLandingData();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        _fetchAllLandingData();
      }
    }
  }

  void _onGlobalDataUpdate() {
    final event = SocketService().dataUpdateNotifier.value;
    if (!mounted || event == null) return;
    if (event.contains('gallery')) {
      _fetchGallery();
    } else if (event.contains('news')) {
      _fetchNews();
    } else if (event.contains('bulletin')) {
      _fetchBulletins();
    } else if (event.contains('course')) {
      _fetchCourses();
    } else if (event.contains('event')) {
      _fetchEvents();
    } else if (event.contains('survey')) {
      _fetchPublicSurveys();
    }
  }

  void _onRealtimeNews(dynamic _) {
    if (mounted) _fetchNews();
  }

  void _onRealtimeBulletins(dynamic _) {
    if (mounted) _fetchBulletins();
  }

  void _onRealtimeCourses(dynamic _) {
    if (mounted) _fetchCourses();
  }

  void _onRealtimeEvents(dynamic _) {
    if (mounted) _fetchEvents();
  }

  void _onRealtimeGallery(dynamic _) {
    if (mounted) _fetchGallery();
  }

  void _onRealtimeSurveys(dynamic _) {
    if (mounted) _fetchPublicSurveys();
  }

  Future<void> _initGuestAndVotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var gid = prefs.getString('cubag_guest_survey_id');
      if (gid == null || gid.isEmpty) {
        gid =
            'guest_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}';
        await prefs.setString('cubag_guest_survey_id', gid);
      }
      _guestId = gid;
      final votedList = prefs.getStringList('cubag_voted_survey_ids') ?? [];
      if (mounted) {
        setState(() {
          _votedSurveyIds.addAll(
            votedList.map((e) => int.tryParse(e) ?? 0).where((e) => e > 0),
          );
        });
      }
    } catch (_) {}
  }

  void _fetchAllLandingData() {
    _fetchNews();
    _fetchBulletins();
    _fetchEvents();
    _fetchCourses();
    _fetchPublicSurveys();
    _fetchGallery();
    _fetchPorts();
    _fetchDirectory();
  }

  Future<void> _fetchPublicSurveys() async {
    setState(() => _loadingSurveys = true);
    try {
      final res = await ApiService().getPublic('surveys/public/active');
      if (res is Map && res['items'] is List) {
        setState(() {
          _publicSurveys = res['items'];
          if (_activeSurveyIdx >= _publicSurveys.length &&
              _publicSurveys.isNotEmpty) {
            _activeSurveyIdx = 0;
          }
        });
      } else if (res is List) {
        setState(() {
          _publicSurveys = res;
          if (_activeSurveyIdx >= _publicSurveys.length &&
              _publicSurveys.isNotEmpty) {
            _activeSurveyIdx = 0;
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingSurveys = false);
  }

  Future<void> _submitGuestVote(dynamic survey) async {
    final surveyId = survey['id'] as int;
    final selected = _selectedOptionMap[surveyId];
    if (selected == null || selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select an option before submitting your vote.',
            style: _outfit(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _submittingSurvey[surveyId] = true);
    try {
      final res = await ApiService().postPublic(
        'surveys/public/$surveyId/respond',
        {
          'answers': {'vote': selected},
          'guest_id': _guestId,
        },
      );

      if (res != null) {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _votedSurveyIds.add(surveyId);
          if (res is Map && res['tallies'] != null) {
            survey['tallies'] = res['tallies'];
            survey['total_votes'] = res['total_votes'];
          }
        });
        await prefs.setStringList(
          'cubag_voted_survey_ids',
          _votedSurveyIds.map((e) => e.toString()).toList(),
        );
        if (mounted) {
          _showVoteSuccessDialog(
            context,
            title: survey['title']?.toString() ?? 'Community Survey',
            selected: selected,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to submit vote. Please try again.',
                style: _outfit(),
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error. Please try again.', style: _outfit()),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _submittingSurvey[surveyId] = false);
  }

  void _showVoteSuccessDialog(
    BuildContext context, {
    required String title,
    required String selected,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(28),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF10b981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10b981),
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Vote Submitted Successfully!',
                textAlign: TextAlign.center,
                style: _outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: _outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _kAccent,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _globalIsDark
                      ? const Color(0xFF1A0F0A)
                      : const Color(0xFFF8F4F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.how_to_vote_rounded,
                      size: 18,
                      color: Color(0xFF10b981),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your Choice: $selected',
                        style: _outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _kText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Thank you for participating. Your response has been securely recorded.',
                textAlign: TextAlign.center,
                style: _inter(fontSize: 13, color: _kMuted, height: 1.45),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrown,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Done',
                    style: _outfit(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchPorts() async {
    try {
      final res = await ApiService().getPublic('members/public/ports');
      if (res is List && res.isNotEmpty && mounted) {
        setState(() => _portsCount = res.length);
      }
    } catch (_) {}
  }

  Future<void> _fetchNews() async {
    setState(() => _loadingNews = true);
    try {
      final res = await ApiService().getPublic('news/public/feed');
      if (res is Map && res['items'] is List) {
        setState(() => _newsArticles = res['items']);
      } else if (res is List) {
        setState(() => _newsArticles = res);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingNews = false);
  }

  Future<void> _fetchBulletins() async {
    setState(() => _loadingBulletins = true);
    try {
      final res = await ApiService().getPublic('news/public/bulletins');
      if (res is Map && res['items'] is List) {
        setState(() => _portBulletins = res['items']);
      } else if (res is List) {
        setState(() => _portBulletins = res);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingBulletins = false);
  }

  Future<void> _fetchEvents() async {
    setState(() => _loadingEvents = true);
    try {
      final res = await ApiService().getPublic('events/public');
      if (res is Map && res['items'] is List) {
        final List all = res['items'];
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        DateTime parseEventDate(dynamic e) {
          try {
            final dStr = e['date']?.toString();
            if (dStr != null && dStr.isNotEmpty) {
              return DateTime.parse(dStr.split('T')[0]);
            }
          } catch (_) {}
          return DateTime(2099, 12, 31);
        }

        final upcomingEvents =
            all
                .where(
                  (e) =>
                      e['is_meeting'] != true &&
                      !parseEventDate(e).isBefore(today),
                )
                .toList()
              ..sort((a, b) => parseEventDate(a).compareTo(parseEventDate(b)));

        final pastEvents =
            all
                .where(
                  (e) =>
                      e['is_meeting'] != true &&
                      parseEventDate(e).isBefore(today),
                )
                .toList()
              ..sort((a, b) => parseEventDate(b).compareTo(parseEventDate(a)));

        final upcomingMeetings =
            all
                .where(
                  (e) =>
                      e['is_meeting'] == true &&
                      !parseEventDate(e).isBefore(today),
                )
                .toList()
              ..sort((a, b) => parseEventDate(a).compareTo(parseEventDate(b)));

        final pastMeetings =
            all
                .where(
                  (e) =>
                      e['is_meeting'] == true &&
                      parseEventDate(e).isBefore(today),
                )
                .toList()
              ..sort((a, b) => parseEventDate(b).compareTo(parseEventDate(a)));

        setState(() {
          _eventsList = [...upcomingEvents, ...pastEvents];
          _meetingsList = [...upcomingMeetings, ...pastMeetings];
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingEvents = false);
  }

  Future<void> _fetchCourses() async {
    setState(() => _loadingCourses = true);
    try {
      final res = await ApiService().getPublic('events/public/courses');
      if (res is Map && res['items'] is List) {
        setState(() => _coursesList = res['items']);
      } else if (res is List) {
        setState(() => _coursesList = res);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingCourses = false);
  }

  Future<void> _fetchGallery() async {
    setState(() => _loadingGallery = true);
    try {
      final res = await ApiService().getPublic('events/public/gallery');
      if (res is Map && res['items'] is List) {
        setState(() => _galleryList = res['items']);
      } else if (res is List) {
        setState(() => _galleryList = res);
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loadingGallery = false);
      _startGalleryAutoScroll();
    }
  }

  void _startGalleryAutoScroll() {
    _galleryAutoTimer?.cancel();
    if (_galleryList.length <= 1) return;
    _galleryAutoTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted ||
          !_galleryScrollCtrl.hasClients ||
          _galleryList.length <= 1) {
        return;
      }
      final max = _galleryScrollCtrl.position.maxScrollExtent;
      final current = _galleryScrollCtrl.offset;
      const double step = 294.0;
      double next = current + step;
      if (next >= max - 10) {
        _galleryScrollCtrl.animateTo(
          0.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      } else {
        _galleryScrollCtrl.animateTo(
          next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _scrollListener() {
    final nowScrolled = _scrollController.offset > 20;
    if (nowScrolled != _scrolled) setState(() => _scrolled = nowScrolled);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SocketService().dataUpdateNotifier.removeListener(_onGlobalDataUpdate);
    SocketService().off('news_updated', _onRealtimeNews);
    SocketService().off('bulletins_updated', _onRealtimeBulletins);
    SocketService().off('courses_updated', _onRealtimeCourses);
    SocketService().off('events_updated', _onRealtimeEvents);
    SocketService().off('gallery_updated', _onRealtimeGallery);
    SocketService().off('surveys_updated', _onRealtimeSurveys);
    _backgroundSyncTimer?.cancel();
    _galleryAutoTimer?.cancel();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _galleryScrollCtrl.dispose();
    _dirSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDirectory([String? query]) async {
    final q = (query ?? _dirSearchCtrl.text).trim();
    try {
      final url = q.isEmpty
          ? 'members/public/members'
          : 'members/public/members?search=${Uri.encodeComponent(q)}';
      final res = await ApiService().getPublic(url);
      if (res is List && mounted) {
        setState(() => _directoryMembers = res);
      }
    } catch (_) {}
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    }
    setState(() => _mobileMenuOpen = false);
  }

  // ────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Listen to ThemeService so entire landing page re-renders dynamically
    Provider.of<ThemeService>(context);
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 950;

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // Scrollable page content
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  SizedBox(
                    height: 72.0 + MediaQuery.of(context).padding.top,
                  ), // header clearance with device status bar
                  // ① Hero
                  _buildHeroSection(size, isMobile),
                  // ② Quick Services
                  _buildQuickServicesSection(isMobile),
                  // ③ Industry Updates
                  _buildIndustryUpdatesSection(isMobile),
                  // ④ Community Surveys & Polls (Guest & Public participation)
                  _buildSurveysSection(isMobile),
                  // ⑤ Member Directory
                  _buildMemberDirectorySection(isMobile),
                  // ⑥ Events & Meetings
                  _buildEventsSection(isMobile),
                  // ⑦ CTI Training
                  _buildCtiTrainingSection(isMobile),
                  // ⑧ Complaints & Tracking Order
                  _buildComplaintsSection(isMobile),
                  // ⑨ Gallery
                  _buildGallerySection(isMobile),
                  // ⑩ Merged Need Help & Footer
                  _buildFooter(isMobile),
                ],
              ),
            ),
          ),

          // Floating scroll-aware header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(context, isMobile),
          ),

          // Mobile navigation drawer overlay
          if (_mobileMenuOpen) _buildMobileMenuDrawer(context),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, bool isMobile) {
    final topPadding = MediaQuery.of(context).padding.top;
    final headerHeight = 72.0 + topPadding;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: headerHeight,
      padding: EdgeInsets.only(
        top: topPadding > 0 ? topPadding + 4 : 0,
        left: isMobile ? 16 : 24,
        right: isMobile ? 16 : 24,
      ),
      decoration: BoxDecoration(
        color: _scrolled
            ? (_globalIsDark
                  ? const Color(0xFF1A0F0A).withAlpha(248)
                  : Colors.white.withAlpha(248))
            : (topPadding > 0
                  ? (_globalIsDark
                        ? const Color(0xFF1A0F0A).withAlpha(220)
                        : Colors.white.withAlpha(220))
                  : Colors.transparent),
        border: Border(
          bottom: BorderSide(
            color: _scrolled ? _kBorder : Colors.transparent,
            width: 1,
          ),
        ),
        boxShadow: _scrolled
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(_globalIsDark ? 50 : 8),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Row(
            children: [
              // Logo
              GestureDetector(
                onTap: () => _scrollTo(_heroKey),
                child: Row(
                  children: [
                    const AppLogo(
                      size: 38,
                      borderRadius: 10,
                      showShadow: false,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'CUBAG',
                      style: _outfit(
                        color: _kText,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Desktop nav
              if (!isMobile) ...[
                _headerLink('Services', () => _scrollTo(_servicesKey)),
                _headerLink('Updates', () => _scrollTo(_updatesKey)),
                _headerLink('Licensed Brokers', () => _scrollTo(_directoryKey)),
                _headerLink('Events', () => _scrollTo(_eventsKey)),
                _headerLink('Register A Course', () => _scrollTo(_trainingKey)),
                _headerLink('Surveys & Polls', () => _scrollTo(_surveysKey)),
                _headerLink('Complaints', () => _scrollTo(_complaintsKey)),
                const SizedBox(width: 8),
              ],

              // Dark/Light Theme Toggle
              Consumer<ThemeService>(
                builder: (context, themeService, _) {
                  final isDark = themeService.isDark;
                  return Tooltip(
                    message: isDark
                        ? 'Switch to Light Mode'
                        : 'Switch to Dark Mode',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => themeService.toggleTheme(),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (c, a) => RotationTransition(
                            turns: a,
                            child: FadeTransition(opacity: a, child: c),
                          ),
                          child: Icon(
                            isDark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            key: ValueKey(isDark),
                            color: isDark ? const Color(0xFFFF5000) : _kBrown,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),

              // Public Header CTAs (Always show Sign In / Join CUBAG on the public landing page)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => context.go('/login'),
                    style: TextButton.styleFrom(
                      foregroundColor: _kText,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      'Sign In',
                      style: _outfit(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton(
                        onPressed: () => context.go('/register'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Join CUBAG',
                          style: _outfit(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              if (isMobile) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => setState(() => _mobileMenuOpen = true),
                  icon: Icon(Icons.menu_rounded, color: _kText, size: 26),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerLink(String text, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          text,
          style: _outfit(
            color: _kMuted,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // MOBILE DRAWER
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildMobileMenuDrawer(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _mobileMenuOpen = false),
        child: Container(
          color: Colors.black.withAlpha(100),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 280,
                height: double.infinity,
                color: _globalIsDark ? const Color(0xFF281710) : Colors.white,
                padding: EdgeInsets.only(
                  top: topPadding > 0 ? topPadding + 16 : 24,
                  bottom: 24,
                  left: 24,
                  right: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'MENU',
                          style: _outfit(
                            color: _kMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _mobileMenuOpen = false),
                          icon: Icon(Icons.close_rounded, color: _kMuted),
                        ),
                      ],
                    ),
                    Divider(color: _kBorder),
                    const SizedBox(height: 8),
                    _drawerLink(
                      'Services',
                      Icons.grid_view_outlined,
                      () => _scrollTo(_servicesKey),
                    ),
                    _drawerLink(
                      'Industry Updates',
                      Icons.article_outlined,
                      () => _scrollTo(_updatesKey),
                    ),
                    _drawerLink(
                      'Find A Clearing Agent',
                      Icons.manage_search_rounded,
                      () => _scrollTo(_directoryKey),
                    ),
                    _drawerLink(
                      'Events & Meetings',
                      Icons.event_outlined,
                      () => _scrollTo(_eventsKey),
                    ),
                    _drawerLink(
                      'Register A Course',
                      Icons.school_outlined,
                      () => _scrollTo(_trainingKey),
                    ),
                    _drawerLink(
                      'Complaints & Tracking',
                      Icons.report_problem_outlined,
                      () => _scrollTo(_complaintsKey),
                    ),
                    _drawerLink(
                      'Surveys & Polls',
                      Icons.how_to_vote_outlined,
                      () => _scrollTo(_surveysKey),
                    ),
                    _drawerLink(
                      'Gallery',
                      Icons.photo_library_outlined,
                      () => _scrollTo(_galleryKey),
                    ),
                    _drawerLink(
                      'Contact',
                      Icons.phone_outlined,
                      () => _scrollTo(_contactKey),
                    ),
                    const Spacer(),
                    Divider(color: _kBorder),
                    const SizedBox(height: 8),
                    // Drawer Theme Toggle Row
                    Consumer<ThemeService>(
                      builder: (context, themeService, _) {
                        final isDark = themeService.isDark;
                        return InkWell(
                          onTap: () => themeService.toggleTheme(),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isDark
                                      ? Icons.light_mode_rounded
                                      : Icons.dark_mode_rounded,
                                  color: isDark
                                      ? const Color(0xFFFF5000)
                                      : _kBrown,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  isDark ? 'Light Theme' : 'Dark Theme',
                                  style: _outfit(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _kText,
                                  ),
                                ),
                                const Spacer(),
                                Switch(
                                  value: isDark,
                                  activeThumbColor: const Color(0xFFFF5000),
                                  onChanged: (_) => themeService.toggleTheme(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Consumer<AuthService>(
                      builder: (context, auth, _) {
                        if (auth.isAuthenticated) {
                          final role = auth.userRole;
                          final isAdmin =
                              role == 'admin' ||
                              role == 'sub_admin' ||
                              role == 'super_admin';
                          final status = auth.membershipStatus
                              .toLowerCase()
                              .trim();
                          final isApproved =
                              status == 'active' || status == 'approved';
                          final isPaid = auth.isRegistrationFeePaid;
                          final isPending =
                              !isAdmin && (!isApproved || !isPaid);

                          final targetRoute = isAdmin
                              ? '/admin/dashboard'
                              : (isPending
                                    ? '/application-documents'
                                    : '/dashboard');
                          final btnLabel = isAdmin
                              ? 'Go to Admin Portal'
                              : (isPending
                                    ? 'Complete My Application'
                                    : 'Go to Member Dashboard');

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() => _mobileMenuOpen = false);
                                    context.go(targetRoute);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isPending
                                        ? const Color(0xFFFF5000)
                                        : _kBrown,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    btnLabel,
                                    style: _outfit(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: () async {
                                    setState(() => _mobileMenuOpen = false);
                                    await auth.logout();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(
                                      color: Colors.redAccent,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'Sign Out',
                                    style: _outfit(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() => _mobileMenuOpen = false);
                                  context.go('/login');
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _kBrown,
                                  side: BorderSide(color: _kBrown, width: 1.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Sign In',
                                  style: _outfit(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() => _mobileMenuOpen = false);
                                  context.go('/register');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kAccent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Join CUBAG',
                                  style: _outfit(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _drawerLink(String text, IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _kBrown),
          const SizedBox(width: 14),
          Text(
            text,
            style: _outfit(
              color: _kText,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // ① HERO SECTION
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildHeroSection(Size size, bool isMobile) {
    return Container(
      key: _heroKey,
      color: _kBg,
      child: Stack(
        children: [
          // Subtle diagonal port/route pattern at ~4% opacity
          Positioned.fill(
            child: CustomPaint(painter: _SubtleRoutePatternPainter()),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 48,
              vertical: isMobile ? 48 : 80,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: isMobile ? _buildMobileHero() : _buildDesktopHero(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Eyebrow label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _kBrown.withAlpha(18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kBrown.withAlpha(40)),
          ),
          child: Text(
            'CUSTOMS BROKERS ASSOCIATION OF GHANA',
            style: _outfit(
              color: _kBrown,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 20),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: _outfit(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.22,
              letterSpacing: -0.5,
            ),
            children: [
              TextSpan(
                text: '🇬🇭 Connecting ',
                style: TextStyle(color: _kText),
              ),
              TextSpan(
                text: 'Customs Clearance\n',
                style: TextStyle(color: _kBrown),
              ),
              TextSpan(
                text: '🌍 Int\'l Trade & ',
                style: TextStyle(color: _kAccent),
              ),
              TextSpan(
                text: 'Freight Forwarding',
                style: TextStyle(color: _kText),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Access CUBAG services, connect with industry professionals, discover training opportunities, and stay informed about Ghana\'s customs and trade industry.',
          textAlign: TextAlign.center,
          style: _inter(color: _kMuted, fontSize: 16, height: 1.65),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => _scrollTo(_servicesKey),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Explore Services',
              style: _outfit(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () => context.go('/register'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kBrown,
              side: BorderSide(color: _kBrown, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Join CUBAG',
              style: _outfit(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHero() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left: Headline + CTAs
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _kBrown.withAlpha(18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kBrown.withAlpha(40)),
                ),
                child: Text(
                  'CUSTOMS BROKERS ASSOCIATION OF GHANA',
                  style: _outfit(
                    color: _kBrown,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              RichText(
                text: TextSpan(
                  style: _outfit(
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    height: 1.18,
                    letterSpacing: -1.0,
                  ),
                  children: [
                    TextSpan(
                      text: 'Connecting ',
                      style: TextStyle(color: _kText),
                    ),
                    TextSpan(
                      text: 'Customs Clearance 🇬🇭\n',
                      style: TextStyle(color: _kBrown),
                    ),
                    TextSpan(
                      text: 'Freight Forwarding & ',
                      style: TextStyle(color: _kText),
                    ),
                    TextSpan(
                      text: '🌍 Int\'l Trade',
                      style: TextStyle(color: _kAccent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Text(
                  'Access CUBAG services, connect with industry professionals, discover training opportunities, and stay informed about Ghana\'s customs and trade industry.',
                  style: _inter(color: _kMuted, fontSize: 18, height: 1.65),
                ),
              ),
              const SizedBox(height: 36),
              Row(
                children: [
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _scrollTo(_servicesKey),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Explore Services',
                        style: _outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => context.go('/register'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kBrown,
                        side: BorderSide(color: _kBrown, width: 1.5),
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Join CUBAG',
                        style: _outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 56),
        // Right: Branded at-a-glance stats panel
        Expanded(flex: 4, child: _buildHeroStatsPanel()),
      ],
    );
  }

  Widget _buildHeroStatsPanel() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CUBAG at a Glance',
            style: _outfit(
              color: _kBrown,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 20),
          _statRow(Icons.people_outline_rounded, '1,200+', 'Active Members'),
          Divider(height: 24, color: _kBorder),
          _statRow(
            Icons.location_on_outlined,
            '$_portsCount',
            'Port & Border Locations',
          ),
          Divider(height: 24, color: _kBorder),
          _statRow(
            Icons.school_outlined,
            _coursesList.isNotEmpty ? '${_coursesList.length}+' : '12+',
            'CTI Courses Offered',
          ),
          Divider(height: 24, color: _kBorder),
          _statRow(
            Icons.directions_boat_outlined,
            'Live',
            'Vessel Tracking & AIS',
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBrown,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Member Login',
                style: _outfit(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String value, String label) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _kBrown.withAlpha(18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: _kBrown),
      ),
      const SizedBox(width: 14),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: _outfit(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: _kText,
            ),
          ),
          Text(label, style: _inter(fontSize: 14, color: _kMuted)),
        ],
      ),
    ],
  );

  // ──────────────────────────────────────────────────────────────────────────
  // ② QUICK SERVICES SECTION
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildQuickServicesSection(bool isMobile) {
    return Container(
      key: _servicesKey,
      color: _kCream,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HOW CAN WE HELP YOU?',
                style: _outfit(
                  color: _kBrown,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Quick Services',
                style: _outfit(
                  color: _kText,
                  fontSize: isMobile ? 28 : 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Find what you need — no account required.',
                style: _inter(color: _kMuted, fontSize: 16),
              ),
              const SizedBox(height: 28),

              // Mobile: 2×3 grid | Desktop: 6-across row
              if (isMobile)
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.92,
                  children: [
                    _serviceCard(
                      'Find A Licensed Broker (Clearing Agent/Forwarder)',
                      'Search verified brokers',
                      Icons.manage_search_rounded,
                      () => _scrollTo(_directoryKey),
                    ),
                    _serviceCard(
                      'Community Polls & Surveys',
                      'Vote & voice your opinion',
                      Icons.how_to_vote_outlined,
                      () => _scrollTo(_surveysKey),
                    ),
                    _serviceCard(
                      'Register A Course',
                      'Professional CTI training',
                      Icons.school_outlined,
                      () => context.go('/guest-services/cti_training'),
                    ),
                    _serviceCard(
                      'Complaints & Tracking',
                      'Lodge & track grievance',
                      Icons.report_problem_outlined,
                      () => _scrollTo(_complaintsKey),
                    ),
                    _serviceCard(
                      'Become a Member',
                      'Join the association',
                      Icons.person_add_outlined,
                      () => context.go('/register'),
                    ),
                    _serviceCard(
                      'Renew Membership',
                      'Extend your membership',
                      Icons.autorenew_rounded,
                      () => context.go('/login'),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _serviceCard(
                        'Find A Broker',
                        'Search verified brokers',
                        Icons.manage_search_rounded,
                        () => _scrollTo(_directoryKey),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _serviceCard(
                        'Public Polls',
                        'Voice opinion & vote',
                        Icons.how_to_vote_outlined,
                        () => _scrollTo(_surveysKey),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _serviceCard(
                        'Register A Course',
                        'Professional CTI training',
                        Icons.school_outlined,
                        () => context.go('/guest-services/cti_training'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _serviceCard(
                        'Complaints & Tracking',
                        'Lodge & track grievance',
                        Icons.report_problem_outlined,
                        () => _scrollTo(_complaintsKey),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _serviceCard(
                        'Become a Member',
                        'Join the association',
                        Icons.person_add_outlined,
                        () => context.go('/register'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _serviceCard(
                        'Renew Membership',
                        'Extend your membership',
                        Icons.autorenew_rounded,
                        () => context.go('/login'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceCard(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Small premium icon container — 48px box, 22px icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _kBrown.withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: _kBrown),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: _outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: _inter(fontSize: 14, color: _kMuted)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Get started',
                        style: _outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _kAccent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: _kAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ③ INDUSTRY UPDATES  (above member directory — mobile-first priority)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildIndustryUpdatesSection(bool isMobile) {
    return Container(
      key: _updatesKey,
      color: _kBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Industry Updates',
                        style: _outfit(
                          color: _kText,
                          fontSize: isMobile ? 26 : 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Stay informed about the latest developments.',
                        style: _inter(color: _kMuted, fontSize: 16),
                      ),
                    ],
                  ),
                  if (!isMobile)
                    _textCta(
                      'View All Updates',
                      () => _showAllUpdatesModal(
                        context,
                        initialTab: _activeUpdatesTab,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Segmented pill control — Brown bg / white text when selected
              _segmentedControl(
                tabs: ['Port News', 'Industry News'],
                active: _activeUpdatesTab,
                onSelect: (i) => setState(() => _activeUpdatesTab = i),
              ),
              const SizedBox(height: 20),

              // Tab content
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _activeUpdatesTab == 0
                    ? _buildPortNewsCards(key: const ValueKey('port'))
                    : _buildIndustryNewsCards(key: const ValueKey('industry')),
              ),

              if (isMobile) ...[
                const SizedBox(height: 16),
                Center(
                  child: _textCta(
                    'View All Updates',
                    () => _showAllUpdatesModal(
                      context,
                      initialTab: _activeUpdatesTab,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAllUpdatesModal(BuildContext context, {int initialTab = 0}) {
    showDialog(
      context: context,
      builder: (ctx) => _AllUpdatesDialog(
        initialTab: initialTab,
        portBulletins: _portBulletins,
        newsArticles: _newsArticles,
      ),
    );
  }

  Widget _buildPortNewsCards({Key? key}) {
    if (_loadingBulletins) {
      return Center(
        key: const ValueKey('loading_bulletins'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
        ),
      );
    }

    if (_portBulletins.isEmpty) {
      return Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kCream,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'No port operational bulletins published at this time.',
          style: _inter(color: _kMuted, fontSize: 15),
        ),
      );
    }

    final bulletins = _portBulletins
        .take(3)
        .map(
          (pb) => {
            'port': pb['port_name']?.toString() ?? 'Port Terminal',
            'code': pb['code']?.toString() ?? 'GHA',
            'notice': pb['notice']?.toString() ?? '',
            'date': 'Live Update',
            'status': pb['status']?.toString() ?? 'Operational',
            'status_color': AppColors.parseHexColor(
              pb['status_color'],
              fallback: const Color(0xFF2E7D32),
            ),
          },
        )
        .toList();

    return Column(
      key: key,
      children: bulletins
          .map(
            (pb) => _updateCard(
              icon: Icons.directions_boat_outlined,
              headline: '${pb['port'] ?? ''} (${pb['code'] ?? ''})',
              body: pb['notice']?.toString() ?? '',
              meta: pb['date']?.toString() ?? '',
              statusLabel: pb['status']?.toString() ?? '',
              statusColor:
                  (pb['status_color'] as Color?) ?? const Color(0xFF2E7D32),
              trailingLabel: 'Read Full Notice',
              onTap: () => _showAllUpdatesModal(context, initialTab: 0),
            ),
          )
          .toList(),
    );
  }

  Widget _buildIndustryNewsCards({Key? key}) {
    if (_loadingNews) {
      return Center(
        key: const ValueKey('loading_news'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
        ),
      );
    }
    final articles = _newsArticles.isNotEmpty
        ? _newsArticles
              .take(3)
              .map(
                (a) => {
                  'title': a['title']?.toString() ?? '',
                  'summary':
                      a['summary']?.toString() ??
                      a['description']?.toString() ??
                      '',
                  'source': a['source']?.toString() ?? 'CUBAG News',
                  'date': a['pubDate']?.toString() ?? 'Recent',
                },
              )
              .toList()
        : [
            {
              'title': 'Ghana Revenue Authority Launches ICUMS 2.0 Automation',
              'source': 'GRA Customs Circular',
              'date': '17 Aug 2026',
              'summary':
                  'New customs clearance upgrades implemented at Tema Port for faster ICUMS processing.',
            },
            {
              'title': 'GPHA Announces Port Fee Tariff Review for Q3 2026',
              'source': 'GPHA Maritime',
              'date': '16 Aug 2026',
              'summary':
                  'GPHA updates vessel handling tariffs across Tema and Takoradi port terminals.',
            },
            {
              'title':
                  'West Africa Maritime Trade Corridors Record 8.5% Growth',
              'source': 'FreightWaves',
              'date': '15 Aug 2026',
              'summary':
                  'Container throughput in agro-exports and raw goods sets record highs for the region.',
            },
          ];

    return Column(
      key: key,
      children: articles
          .map(
            (a) => _updateCard(
              icon: Icons.article_outlined,
              headline: a['title']!,
              body: a['summary']!,
              meta: '${a['source']}  ·  ${a['date']}',
              trailingLabel: 'Read More',
              onTap: () => _showAllUpdatesModal(context, initialTab: 1),
            ),
          )
          .toList(),
    );
  }

  Widget _updateCard({
    required IconData icon,
    required String headline,
    required String body,
    required String meta,
    String? statusLabel,
    Color? statusColor,
    String? trailingLabel,
    VoidCallback? onTap,
    Key? key,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kCream,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kBrown.withAlpha(18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: _kBrown),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            headline,
                            style: _outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _kText,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (statusLabel != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (statusColor ?? _kBrown).withAlpha(20),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusLabel,
                              style: _outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: statusColor ?? _kBrown,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      body,
                      style: _inter(fontSize: 15, color: _kMuted, height: 1.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            meta,
                            style: _inter(fontSize: 13, color: _kMuted),
                          ),
                        ),
                        if (trailingLabel != null)
                          Text(
                            trailingLabel,
                            style: _outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _kAccent,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ④ FIND A CLEARING AGENT DIRECTORY & SEARCH
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildMemberDirectorySection(bool isMobile) {
    return Container(
      key: _directoryKey,
      color: _kCream,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FIND A LICENSED BROKER (CLEARING AGENT/FORWARDER)',
                          style: _outfit(
                            color: _kBrown,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Find A Licensed Broker (Clearing Agent/Forwarder)',
                          style: _outfit(
                            color: _kText,
                            fontSize: isMobile ? 24 : 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search accredited CUBAG licensed customs brokers, clearing agents, and freight forwarders across Ghana.',
                          style: _inter(color: _kMuted, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Search field + Search Action
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _kCardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorder),
                      ),
                      child: TextField(
                        controller: _dirSearchCtrl,
                        onSubmitted: (query) => _showAllDirectoryModal(
                          context,
                          initialQuery: query.trim(),
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Search by broker name, clearing agency, license #, or port of operation...',
                          hintStyle: _inter(
                            color: _kMuted,
                            fontSize: isMobile ? 15 : 16,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: _kBrown,
                            size: 20,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showAllDirectoryModal(
                      context,
                      initialQuery: _dirSearchCtrl.text.trim(),
                    ),
                    icon: const Icon(Icons.search_rounded, size: 16),
                    label: Text(
                      isMobile ? 'Search' : 'Search Directory',
                      style: _outfit(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBrown,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 16 : 24,
                        vertical: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Action CTA: View Full Directory
              Center(
                child: SizedBox(
                  width: isMobile ? double.infinity : 320,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAllDirectoryModal(
                      context,
                      initialQuery: _dirSearchCtrl.text.trim(),
                    ),
                    icon: const Icon(Icons.people_outline_rounded, size: 18),
                    label: Text(
                      'View Full Agent Directory',
                      style: _outfit(
                        fontSize: 16.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllDirectoryModal(
    BuildContext context, {
    String initialQuery = '',
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _AllDirectoryDialog(
        membersList: _directoryMembers,
        initialQuery: initialQuery,
        onVerifyMember: (m) => _showMemberVerificationModal(m),
      ),
    );
  }

  void _showMemberVerificationModal(Map<String, dynamic> m) {
    final company =
        m['company']?.toString() ?? m['name']?.toString() ?? 'CUBAG Member';
    final name = m['name']?.toString() ?? '';
    final port = m['primary_port']?.toString() ?? 'Tema Port';
    final type = m['member_type']?.toString() ?? 'Licentiate';
    final phone = m['phone']?.toString() ?? '';
    final email = m['email']?.toString() ?? '';
    final location = m['location']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(28),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF10b981).withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF10b981),
                  size: 48,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Accredited Customs Broker',
                style: _outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Customs Brokers Association of Ghana (CUBAG)',
                style: _inter(fontSize: 14, color: _kMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _kCream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _modalDetailRow('Company Entity', company),
                    if (name.isNotEmpty && name != company) ...[
                      const Divider(height: 16),
                      _modalDetailRow('Lead Broker / Contact', name),
                    ],
                    const Divider(height: 16),
                    _modalDetailRow('Primary Port', port),
                    const Divider(height: 16),
                    _modalDetailRow('Member Category', type),
                    if (location.isNotEmpty) ...[
                      const Divider(height: 16),
                      _modalDetailRow('Office Location', location),
                    ],
                    if (phone.isNotEmpty) ...[
                      const Divider(height: 16),
                      _modalDetailRow('Direct Phone', phone),
                    ],
                    if (email.isNotEmpty) ...[
                      const Divider(height: 16),
                      _modalDetailRow('Official Email', email, isEmail: true),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrown,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Close',
                    style: _outfit(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modalDetailRow(String label, String value, {bool isEmail = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: _inter(fontSize: 14.5, color: _kMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: SelectableText(
              value,
              style: _outfit(
                fontSize: isEmail ? 14.5 : 15,
                fontWeight: FontWeight.bold,
                color: _kText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ⑤ EVENTS & MEETINGS
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildEventsSection(bool isMobile) {
    return Container(
      key: _eventsKey,
      color: _kBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Events & Meetings',
                        style: _outfit(
                          color: _kText,
                          fontSize: isMobile ? 26 : 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upcoming CUBAG events and scheduled meetings.',
                        style: _inter(color: _kMuted, fontSize: 16),
                      ),
                    ],
                  ),
                  if (!isMobile)
                    _textCta(
                      'View All',
                      () => _showAllEventsModal(
                        context,
                        initialTab: _activeEventsTab,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              _segmentedControl(
                tabs: ['Events', 'Meetings'],
                active: _activeEventsTab,
                onSelect: (i) => setState(() => _activeEventsTab = i),
              ),
              const SizedBox(height: 20),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _loadingEvents
                    ? Center(
                        key: const ValueKey('loading_events'),
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _kAccent,
                          ),
                        ),
                      )
                    : _activeEventsTab == 0
                    ? _buildEventCards(key: const ValueKey('ev'))
                    : _buildMeetingCards(key: const ValueKey('mt')),
              ),

              if (isMobile) ...[
                const SizedBox(height: 16),
                Center(
                  child: _textCta(
                    'View All',
                    () => _showAllEventsModal(
                      context,
                      initialTab: _activeEventsTab,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAllEventsModal(BuildContext context, {int initialTab = 0}) {
    showDialog(
      context: context,
      builder: (ctx) => _AllEventsDialog(
        initialTab: initialTab,
        eventsList: _eventsList,
        meetingsList: _meetingsList,
      ),
    );
  }

  Widget _buildEventCards({Key? key}) {
    if (_eventsList.isEmpty) {
      return Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kCream,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'No upcoming events scheduled at this time.',
          style: _inter(color: _kMuted, fontSize: 15),
        ),
      );
    }

    final previewList = _eventsList.take(3).toList();

    return Column(
      key: key,
      children: previewList.map<Widget>((e) {
        String rawDate = e['date']?.toString() ?? '2026-08-24';
        String day = rawDate;
        String year = '2026';
        if (rawDate.contains('-')) {
          final parts = rawDate.split('-');
          if (parts.length >= 3) {
            year = parts[0];
            day = '${parts[2]} ${_monthName(parts[1])}';
          }
        }
        return _eventCard(
          e['title']?.toString() ?? '',
          day,
          year,
          e['time']?.toString() ?? '10:00 AM',
          e['location']?.toString() ?? 'Accra',
          onTap: () => _showAllEventsModal(context, initialTab: 0),
        );
      }).toList(),
    );
  }

  Widget _buildMeetingCards({Key? key}) {
    if (_meetingsList.isEmpty) {
      return Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kCream,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'No upcoming executive meetings scheduled at this time.',
          style: _inter(color: _kMuted, fontSize: 15),
        ),
      );
    }

    final previewList = _meetingsList.take(3).toList();

    return Column(
      key: key,
      children: previewList.map<Widget>((e) {
        String rawDate = e['date']?.toString() ?? '2026-08-28';
        String day = rawDate;
        String year = '2026';
        if (rawDate.contains('-')) {
          final parts = rawDate.split('-');
          if (parts.length >= 3) {
            year = parts[0];
            day = '${parts[2]} ${_monthName(parts[1])}';
          }
        }
        return _eventCard(
          e['title']?.toString() ?? '',
          day,
          year,
          e['time']?.toString() ?? '10:00 AM',
          e['location']?.toString() ?? 'Accra',
          onTap: () => _showAllEventsModal(context, initialTab: 1),
        );
      }).toList(),
    );
  }

  static String _monthName(String m) {
    switch (m) {
      case '01':
        return 'Jan';
      case '02':
        return 'Feb';
      case '03':
        return 'Mar';
      case '04':
        return 'Apr';
      case '05':
        return 'May';
      case '06':
        return 'Jun';
      case '07':
        return 'Jul';
      case '08':
        return 'Aug';
      case '09':
        return 'Sep';
      case '10':
        return 'Oct';
      case '11':
        return 'Nov';
      case '12':
        return 'Dec';
      default:
        return 'Aug';
    }
  }

  Widget _eventCard(
    String title,
    String day,
    String year,
    String time,
    String location, {
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kCream,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date badge
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _kAccent.withAlpha(22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      day,
                      textAlign: TextAlign.center,
                      style: _outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _kAccent,
                      ),
                    ),
                    Text(
                      year,
                      style: _outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _kAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _kText,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.schedule_outlined, size: 13, color: _kMuted),
                        const SizedBox(width: 4),
                        Text(time, style: _inter(fontSize: 14, color: _kMuted)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: _kMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location,
                            style: _inter(fontSize: 14, color: _kMuted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'View Details →',
                      style: _outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _kAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ⑥ CTI TRAINING
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCtiTrainingSection(bool isMobile) {
    return Container(
      key: _trainingKey,
      color: _kCream,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'REGISTER A COURSE',
                          style: _outfit(
                            color: _kBrown,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Register A Course',
                          style: _outfit(
                            color: _kText,
                            fontSize: isMobile ? 26 : 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Professional CTI customs & trade certification courses open for enrolment.',
                          style: _inter(color: _kMuted, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 16),
                    _textCta(
                      'View All Courses',
                      () => _showAllCoursesModal(context),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 28),

              if (_loadingCourses)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kAccent,
                    ),
                  ),
                )
              else if (_coursesList.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'No CTI training courses currently open for enrolment.',
                    style: _inter(color: _kMuted, fontSize: 15),
                  ),
                )
              else if (isMobile)
                Column(
                  children: _coursesList
                      .take(3)
                      .map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ctiCourseCard(
                            c as Map<dynamic, dynamic>,
                            onTap: () => _showAllCoursesModal(context),
                          ),
                        ),
                      )
                      .toList(),
                )
              else
                Builder(
                  builder: (context) {
                    final previewList = _coursesList.take(3).toList();
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: previewList
                          .asMap()
                          .entries
                          .map(
                            (e) => Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: e.key < previewList.length - 1
                                      ? 16
                                      : 0,
                                ),
                                child: _ctiCourseCard(
                                  e.value as Map<dynamic, dynamic>,
                                  onTap: () => _showAllCoursesModal(context),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),

              if (isMobile) ...[
                const SizedBox(height: 8),
                Center(
                  child: _textCta(
                    'View All Courses',
                    () => _showAllCoursesModal(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAllCoursesModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _AllCoursesDialog(coursesList: _coursesList),
    );
  }

  Widget _ctiCourseCard(Map<dynamic, dynamic> c, {VoidCallback? onTap}) {
    return Material(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kBrown.withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.school_outlined, size: 20, color: _kBrown),
              ),
              const SizedBox(height: 14),
              Text(
                c['title']?.toString() ?? '',
                style: _outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kText,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              _metaRow(
                Icons.calendar_today_outlined,
                c['start_date']?.toString() ??
                    c['date']?.toString() ??
                    'Upcoming',
              ),
              const SizedBox(height: 5),
              _metaRow(
                Icons.schedule_outlined,
                '${c['duration'] ?? '4 Weeks'} · ${c['mode'] ?? 'Hybrid'}',
              ),
              const SizedBox(height: 5),
              _metaRow(
                Icons.payments_outlined,
                c['fee']?.toString() ?? 'GHS 1,500',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onTap ?? () => _showAllCoursesModal(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kBrown,
                        side: BorderSide(color: _kBrown, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Details',
                        style: _outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final courseTitle = (c['title'] ?? '')
                            .toString()
                            .trim();
                        final uri = courseTitle.isNotEmpty
                            ? '/guest-services/cti_training?course=${Uri.encodeComponent(courseTitle)}'
                            : '/guest-services/cti_training';
                        context.go(uri);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Register',
                        style: _outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 13, color: _kMuted),
      const SizedBox(width: 5),
      Text(text, style: _inter(fontSize: 14, color: _kMuted)),
    ],
  );

  // ──────────────────────────────────────────────────────────────────────────
  // ⑦ COMPLAINTS & TRACKING ORDER SECTION
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildComplaintsSection(bool isMobile) {
    return Container(
      key: _complaintsKey,
      color: _kBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DISPUTE & GRIEVANCE REDRESSAL',
                          style: _outfit(
                            color: _kBrown,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Complaints & Tracking Order',
                          style: _outfit(
                            color: _kText,
                            fontSize: isMobile ? 24 : 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lodge an official grievance against cargo clearance delays, demurrage disputes, or broker misconduct — or track the live status of your existing complaint order in real time.',
                          style: _inter(color: _kMuted, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              if (isMobile) ...[
                _buildComplaintTrackingCard(isMobile),
                const SizedBox(height: 16),
                _buildLodgeComplaintCtaCard(isMobile),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildComplaintTrackingCard(isMobile),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: _buildLodgeComplaintCtaCard(isMobile),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _homeTrackComplaint() async {
    final query = _homeTrackCtrl.text.trim().toUpperCase();
    if (query.isEmpty) {
      setState(() {
        _homeTrackError =
            'Please enter your Complaint Tracking ID (e.g. CMP-2026-12345).';
        _homeTrackResult = null;
      });
      return;
    }

    setState(() {
      _homeTracking = true;
      _homeTrackError = null;
    });

    try {
      final res = await ApiService().getPublic('complaints/track/$query');
      if (!mounted) return;
      if (res != null && res['success'] == true && res['data'] != null) {
        setState(() {
          _homeTrackResult = res['data'] as Map<String, dynamic>;
          _homeTrackError = null;
          _homeTracking = false;
        });
      } else {
        setState(() {
          _homeTrackResult = null;
          _homeTrackError =
              res?['message']?.toString() ??
              'No complaint found with ID: $query';
          _homeTracking = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _homeTrackResult = null;
        _homeTrackError =
            'Unable to fetch complaint status. Please verify the ID.';
        _homeTracking = false;
      });
    }
  }

  Widget _buildComplaintTrackingCard(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_globalIsDark ? 30 : 6),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kBrown.withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.track_changes_rounded,
                  color: _kBrown,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Track Complaint Order Status',
                      style: _outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _kText,
                      ),
                    ),
                    Text(
                      'Enter your tracking ID for live investigation updates',
                      style: _inter(fontSize: 14, color: _kMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Tracking Input Bar
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _kCream,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _kBorder),
                  ),
                  child: TextField(
                    controller: _homeTrackCtrl,
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _homeTrackComplaint(),
                    style: GoogleFonts.spaceMono(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kText,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. CMP-2026-92945',
                      hintStyle: GoogleFonts.spaceMono(
                        fontSize: 15,
                        color: _kMuted,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: _kBrown,
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _homeTracking ? null : _homeTrackComplaint,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrown,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _homeTracking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Track Order',
                          style: _outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.5,
                          ),
                        ),
                ),
              ),
            ],
          ),

          if (_homeTrackError != null) ...[
            const SizedBox(height: 12),
            Text(
              _homeTrackError!,
              style: _inter(color: const Color(0xFFC62828), fontSize: 14),
            ),
          ],

          if (_homeTrackResult != null) ...[
            const SizedBox(height: 20),
            Divider(color: _kBorder),
            const SizedBox(height: 14),

            // Live result preview
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _homeTrackResult!['complaint_id']?.toString() ?? '',
                  style: GoogleFonts.spaceMono(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: _kBrown,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _kAccent.withAlpha(25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    (_homeTrackResult!['status'] ?? 'Received')
                        .toString()
                        .toUpperCase(),
                    style: _outfit(
                      color: _kAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _homeTrackResult!['subject']?.toString() ?? '',
              style: _outfit(
                fontSize: 15.5,
                fontWeight: FontWeight.bold,
                color: _kText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Port: ${_homeTrackResult!['port'] ?? 'GHA'} · Category: ${_homeTrackResult!['category'] ?? ''}',
              style: _inter(fontSize: 14, color: _kMuted),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.go(
                  '/complaints/track/${_homeTrackResult!['complaint_id']}',
                ),
                icon: Icon(Icons.visibility_outlined, size: 16, color: _kBrown),
                label: Text(
                  'View Full Timeline & Evidence',
                  style: _outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _kBrown,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _kBrown.withAlpha(120)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLodgeComplaintCtaCard(bool isMobile) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_globalIsDark ? 30 : 6),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kAccent.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.track_changes_rounded,
                  color: _kAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need to Lodge a Complaint?',
                      style: _outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _kText,
                      ),
                    ),
                    Text(
                      'Direct Secretariat Grievance Redressal',
                      style: _inter(fontSize: 14, color: _kMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _bulletPoint(
            'Grievance investigation for customs tariff & demurrage disputes.',
          ),
          const SizedBox(height: 8),
          _bulletPoint('Strict enforcement of CUBAG broker code of ethics.'),
          const SizedBox(height: 8),
          _bulletPoint(
            'Instant Complaint ID issued for transparent order tracking.',
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => context.go('/complaints'),
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: Text(
                'Lodge A Complaint Now',
                style: _outfit(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline_rounded, size: 16, color: _kAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: _inter(fontSize: 14.5, color: _kMuted, height: 1.4),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ⑧ GALLERY  (photographic cards with Left/Right arrow navigation & lightbox)
  // ──────────────────────────────────────────────────────────────────────────
  void _scrollGallery(bool forward) {
    if (!_galleryScrollCtrl.hasClients) return;
    const double delta = 294.0;
    final max = _galleryScrollCtrl.position.maxScrollExtent;
    final current = _galleryScrollCtrl.offset;
    double target;
    if (forward) {
      target = current + delta;
      if (target > max + 10) target = 0.0;
    } else {
      target = current - delta;
      if (target < -10) target = max;
    }
    _galleryScrollCtrl.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _floatingGalleryArrow({
    required IconData icon,
    required VoidCallback onTap,
    required bool isLeft,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(235),
            shape: BoxShape.circle,
            border: Border.all(color: _kBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(25),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, size: 20, color: _kBrown),
        ),
      ),
    );
  }

  void _showPhotoLightbox(int initialIdx) {
    if (_galleryList.isEmpty) return;
    int currentIdx = initialIdx.clamp(0, _galleryList.length - 1);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final item = _galleryList[currentIdx];
          final imgUrl = item['image_url']?.toString() ?? '';
          final title = item['title']?.toString() ?? 'CUBAG Photo';
          final sub =
              item['category']?.toString() ??
              item['sub']?.toString() ??
              'Gallery';
          final desc = item['description']?.toString() ?? '';

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 800,
                  maxHeight: 720,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(60),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        color: Colors.white,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _kAccent.withAlpha(25),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    sub,
                                    style: _outfit(
                                      color: _kAccent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${currentIdx + 1} / ${_galleryList.length}',
                                  style: _inter(fontSize: 14, color: _kMuted),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                size: 22,
                                color: _kText,
                              ),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: _kBorder),

                      // Image with side arrows
                      Flexible(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: double.infinity,
                              color: Colors.black,
                              constraints: const BoxConstraints(maxHeight: 460),
                              child: imgUrl.isNotEmpty
                                  ? CorsImageWidget(
                                      url: ApiService.resolveImageUrl(imgUrl),
                                      fit: BoxFit.contain,
                                      errorWidget: const Center(
                                        child: Icon(
                                          Icons.photo_outlined,
                                          size: 48,
                                          color: Colors.white30,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: _kBrown,
                                      child: const Center(
                                        child: Icon(
                                          Icons.photo_library_outlined,
                                          size: 54,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ),
                            ),
                            if (_galleryList.length > 1) ...[
                              Positioned(
                                left: 12,
                                child: IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.all(10),
                                  ),
                                  icon: const Icon(
                                    Icons.chevron_left_rounded,
                                    size: 26,
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      currentIdx =
                                          (currentIdx -
                                              1 +
                                              _galleryList.length) %
                                          _galleryList.length;
                                    });
                                  },
                                ),
                              ),
                              Positioned(
                                right: 12,
                                child: IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.all(10),
                                  ),
                                  icon: const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 26,
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      currentIdx =
                                          (currentIdx + 1) %
                                          _galleryList.length;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Caption bar
                      Container(
                        padding: const EdgeInsets.all(20),
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: _outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _kText,
                              ),
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                desc,
                                style: _inter(fontSize: 15, color: _kMuted),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PUBLIC SURVEYS & POLLS SECTION (FOR GUESTS & MEMBERS)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildSurveysSection(bool isMobile) {
    return Container(
      key: _surveysKey,
      color: _kCream,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _kAccent.withValues(
                              alpha: _globalIsDark ? 0.2 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _kAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.how_to_vote_rounded,
                                size: 14,
                                color: _kAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'COMMUNITY OPINION & POLLS',
                                style: _outfit(
                                  color: _kAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Have Your Say — Public Surveys',
                          style: _outfit(
                            color: _kText,
                            fontSize: isMobile ? 26 : 34,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Open to general public guests and members. Help shape Ghana\'s trade, port logistics, and customs policies.',
                          style: _inter(
                            color: _kMuted,
                            fontSize: isMobile ? 15 : 17,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Multi-survey selector tabs if multiple polls exist
              if (_publicSurveys.length > 1) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_publicSurveys.length, (idx) {
                      final s = _publicSurveys[idx];
                      final isSelected = _activeSurveyIdx == idx;
                      final isVoted = _votedSurveyIds.contains(s['id']);
                      final surveyTitle =
                          s['title']?.toString() ?? 'Survey ${idx + 1}';
                      final displayTitle = surveyTitle.length > 28
                          ? '${surveyTitle.substring(0, 28)}...'
                          : surveyTitle;

                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: InkWell(
                          onTap: () => setState(() => _activeSurveyIdx = idx),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (_globalIsDark
                                        ? const Color(0xFFFF5000)
                                        : const Color(0xFF6B3E26))
                                  : _kCardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? (_globalIsDark
                                          ? const Color(0xFFFF5000)
                                          : const Color(0xFF6B3E26))
                                    : _kBorder,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color:
                                            (_globalIsDark
                                                    ? const Color(0xFFFF5000)
                                                    : const Color(0xFF6B3E26))
                                                .withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Row(
                              children: [
                                Text(
                                  displayTitle,
                                  style: _outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isSelected ? Colors.white : _kText,
                                  ),
                                ),
                                if (isVoted) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 14,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF10b981),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Content Area
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _loadingSurveys && _publicSurveys.isEmpty
                    ? Center(
                        key: const ValueKey('loading_surveys'),
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: _kAccent,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Loading active community polls...',
                                style: _outfit(color: _kMuted, fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _publicSurveys.isEmpty
                    ? _buildNoPublicSurveysCard(isMobile)
                    : _buildActiveSurveyCard(
                        _publicSurveys[_activeSurveyIdx.clamp(
                          0,
                          _publicSurveys.length - 1,
                        )],
                        isMobile,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoPublicSurveysCard(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 24 : 40),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _globalIsDark ? 0.2 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.poll_outlined, size: 36, color: _kAccent),
          ),
          const SizedBox(height: 16),
          Text(
            'No Active Public Polls at the Moment',
            style: _outfit(
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 19 : 22,
              color: _kText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Text(
              'Check back soon for new public consultations, stakeholder surveys, and industry votes.',
              style: _inter(fontSize: 16, color: _kMuted, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSurveyCard(dynamic survey, bool isMobile) {
    final surveyId = survey['id'] as int;
    final title = survey['title']?.toString() ?? 'Community Survey';
    final desc = survey['description']?.toString() ?? '';
    final type = survey['type']?.toString() ?? 'Survey';
    final deadline = survey['deadline']?.toString();
    final coverImage = survey['cover_image']?.toString();
    final totalVotes = (survey['total_votes'] as num?)?.toInt() ?? 0;
    final tallies = survey['tallies'] is Map
        ? Map<String, dynamic>.from(survey['tallies'])
        : <String, dynamic>{};
    final avgStars = (survey['average_stars'] as num?)?.toDouble() ?? 0.0;
    final isVoted = _votedSurveyIds.contains(surveyId);
    final isSubmitting = _submittingSurvey[surveyId] == true;

    // Parse options
    List<dynamic> options = [];
    if (survey['options'] is List) {
      options = survey['options'] as List<dynamic>;
    } else if (survey['options'] != null &&
        survey['options'].toString().trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(survey['options'].toString());
        if (decoded is List) {
          options = decoded;
        }
      } catch (_) {}
    }

    final isYesNo =
        options.length == 2 &&
        options.any(
          (o) => (o is Map && o['name']?.toString().toLowerCase() == 'yes'),
        );
    final isStarRating = options.isEmpty;
    final selectedOption = _selectedOptionMap[surveyId];

    return Container(
      key: ValueKey('survey_$surveyId'),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _globalIsDark ? 0.25 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Optional Cover Banner
            if (coverImage != null && coverImage.isNotEmpty)
              Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: coverImage,
                    width: double.infinity,
                    height: isMobile ? 140 : 180,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            _kCardBg.withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

            Padding(
              padding: EdgeInsets.all(isMobile ? 20 : 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Tags Bar
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _kBrown.withValues(
                            alpha: _globalIsDark ? 0.2 : 0.1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _kBrown.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          type.toUpperCase(),
                          style: _outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _kBrown,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (deadline != null && deadline.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _kMuted.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 12,
                                color: _kMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Deadline: $deadline',
                                style: _outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _kMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Survey Title & Description
                  Text(
                    title,
                    style: _outfit(
                      fontWeight: FontWeight.w900,
                      fontSize: isMobile ? 22 : 28,
                      color: _kText,
                      height: 1.2,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      desc,
                      style: _inter(
                        fontSize: isMobile ? 16 : 17,
                        color: _kMuted,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Divider(color: _kBorder.withValues(alpha: 0.6)),
                  const SizedBox(height: 20),

                  // Voting form vs Live Results
                  if (isVoted)
                    _buildSurveyLiveResults(
                      survey,
                      isMobile,
                      totalVotes,
                      tallies,
                      avgStars,
                      options,
                    )
                  else
                    _buildSurveyVoteForm(
                      survey,
                      isMobile,
                      isYesNo,
                      isStarRating,
                      options,
                      selectedOption,
                      isSubmitting,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurveyVoteForm(
    dynamic survey,
    bool isMobile,
    bool isYesNo,
    bool isStarRating,
    List<dynamic> options,
    String? selectedOption,
    bool isSubmitting,
  ) {
    final surveyId = survey['id'] as int;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select your response to vote as a guest or member:',
          style: _outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _kText,
          ),
        ),
        const SizedBox(height: 16),

        if (isYesNo)
          Row(
            children: [
              Expanded(
                child: _buildVoteChoiceTile(
                  surveyId: surveyId,
                  optionName: 'Yes',
                  icon: Icons.thumb_up_alt_rounded,
                  isSelected: selectedOption?.toLowerCase() == 'yes',
                  activeColor: const Color(0xFF10b981),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildVoteChoiceTile(
                  surveyId: surveyId,
                  optionName: 'No',
                  icon: Icons.thumb_down_alt_rounded,
                  isSelected: selectedOption?.toLowerCase() == 'no',
                  activeColor: const Color(0xFFef4444),
                ),
              ),
            ],
          )
        else if (isStarRating)
          _buildStarVotingWidget(surveyId, selectedOption)
        else
          Column(
            children: options.map((opt) {
              final name = opt is Map
                  ? (opt['name']?.toString() ?? '')
                  : opt.toString();
              final photo = opt is Map ? opt['photo']?.toString() : null;
              final isSelected = selectedOption == name;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () =>
                      setState(() => _selectedOptionMap[surveyId] = name),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _kAccent.withValues(
                              alpha: _globalIsDark ? 0.15 : 0.08,
                            )
                          : _globalIsDark
                          ? const Color(0xFF1A0F0A)
                          : const Color(0xFFF8F4F0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? _kAccent : _kBorder,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (photo != null && photo.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: CachedNetworkImage(
                              imageUrl: photo,
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => CircleAvatar(
                                radius: 19,
                                backgroundColor: _kAccent.withValues(
                                  alpha: 0.2,
                                ),
                                child: Text(
                                  name.isNotEmpty ? name[0] : '?',
                                  style: _outfit(
                                    color: _kAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            style: _outfit(
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 17,
                              color: isSelected
                                  ? (_globalIsDark
                                        ? Colors.white
                                        : const Color(0xFF6B3E26))
                                  : _kText,
                            ),
                          ),
                        ),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? _kAccent : Colors.transparent,
                            border: Border.all(
                              color: isSelected
                                  ? _kAccent
                                  : _kMuted.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 24),

        // Centered Submit Button
        Center(
          child: SizedBox(
            height: 48,
            width: isMobile ? double.infinity : 280,
            child: ElevatedButton.icon(
              onPressed: isSubmitting ? null : () => _submitGuestVote(survey),
              icon: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.how_to_vote_rounded, size: 18),
              label: Text(
                isSubmitting ? 'Recording Vote...' : 'Submit Vote',
                style: _outfit(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoteChoiceTile({
    required int surveyId,
    required String optionName,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
  }) {
    return InkWell(
      onTap: () => setState(() => _selectedOptionMap[surveyId] = optionName),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: _globalIsDark ? 0.2 : 0.1)
              : (_globalIsDark
                    ? const Color(0xFF1A0F0A)
                    : const Color(0xFFF8F4F0)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeColor : _kBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: isSelected ? activeColor : _kMuted),
            const SizedBox(height: 8),
            Text(
              optionName,
              style: _outfit(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                color: isSelected ? activeColor : _kText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarVotingWidget(int surveyId, String? selectedOption) {
    final currentVal = int.tryParse(selectedOption ?? '0') ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _globalIsDark
            ? const Color(0xFF1A0F0A)
            : const Color(0xFFF8F4F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (idx) {
              final starNum = idx + 1;
              final filled = starNum <= currentVal;
              return IconButton(
                iconSize: 36,
                onPressed: () =>
                    setState(() => _selectedOptionMap[surveyId] = '$starNum'),
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: filled
                      ? const Color(0xFFf59e0b)
                      : _kMuted.withValues(alpha: 0.5),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            currentVal > 0
                ? '$currentVal / 5 Stars Selected'
                : 'Tap to rate from 1 to 5 stars',
            style: _outfit(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: currentVal > 0 ? const Color(0xFFf59e0b) : _kMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSurveyLiveResults(
    dynamic survey,
    bool isMobile,
    int totalVotes,
    Map<String, dynamic> tallies,
    double avgStars,
    List<dynamic> options,
  ) {
    final maxVotes = tallies.values.fold<int>(
      0,
      (m, v) => math.max(m, (v as num).toInt()),
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        color: _globalIsDark
            ? const Color(0xFF1A0F0A)
            : const Color(0xFFF8F4F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10b981).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF10b981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your response was recorded!',
                      style: _outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF10b981),
                      ),
                    ),
                    Text(
                      'Here are the live results from all voters.',
                      style: _inter(fontSize: 14, color: _kMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: _kBorder.withValues(alpha: 0.5)),
          const SizedBox(height: 16),

          if (avgStars > 0 && options.isEmpty) ...[
            Center(
              child: Column(
                children: [
                  Text(
                    'Average Rating Score',
                    style: _outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    avgStars.toStringAsFixed(1),
                    style: _outfit(
                      fontSize: 50,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFf59e0b),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final filled = i < avgStars;
                      return Icon(
                        filled
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: const Color(0xFFf59e0b),
                        size: 26,
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Based on $totalVotes ratings',
                    style: _inter(fontSize: 14, color: _kMuted),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...tallies.entries.map((entry) {
              final optName = entry.key.toString();
              final count = (entry.value as num).toInt();
              final pct = totalVotes > 0 ? (count / totalVotes) : 0.0;
              final barPct = maxVotes > 0 ? (count / maxVotes) : 0.0;
              final isLeader = count == maxVotes && count > 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isLeader) ...[
                          const Icon(
                            Icons.emoji_events_rounded,
                            size: 16,
                            color: Color(0xFFf59e0b),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            optName,
                            style: _outfit(
                              fontSize: 16,
                              fontWeight: isLeader
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: isLeader
                                  ? (_globalIsDark
                                        ? const Color(0xFFFF5000)
                                        : const Color(0xFF6B3E26))
                                  : _kText,
                            ),
                          ),
                        ),
                        Text(
                          '$count votes',
                          style: _outfit(fontSize: 14, color: _kMuted),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${(pct * 100).toStringAsFixed(1)}%',
                            style: _outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _kAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: barPct.clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: _kMuted.withValues(alpha: 0.12),
                        color: isLeader
                            ? _kAccent
                            : _kAccent.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildGallerySection(bool isMobile) {
    return Container(
      key: _galleryKey,
      color: _kBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 56,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gallery',
                    style: _outfit(
                      color: _kText,
                      fontSize: isMobile ? 26 : 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'CUBAG events, training, and port operations.',
                    style: _inter(color: _kMuted, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (_loadingGallery)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kAccent,
                    ),
                  ),
                )
              else if (_galleryList.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _kCream,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'No gallery photos published at this time.',
                    style: _inter(color: _kMuted, fontSize: 15),
                  ),
                )
              else
                // Horizontal scroll row with floating overlay arrows
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: isMobile ? 190 : 230,
                      child: ListView.separated(
                        controller: _galleryScrollCtrl,
                        scrollDirection: Axis.horizontal,
                        itemCount: _galleryList.length,
                        separatorBuilder: (context, i) =>
                            const SizedBox(width: 14),
                        itemBuilder: (context, i) {
                          final item = _galleryList[i];
                          final Color g0 = AppColors.parseHexColor(
                            item['grad_start'],
                            fallback: const Color(0xFF6B3E26),
                          );
                          final Color g1 = AppColors.parseHexColor(
                            item['grad_end'],
                            fallback: const Color(0xFF3E2418),
                          );
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _showPhotoLightbox(i),
                            child: _galleryCard(
                              title: item['title']?.toString() ?? '',
                              subtitle:
                                  item['category']?.toString() ??
                                  item['sub']?.toString() ??
                                  'CUBAG',
                              gradStart: g0,
                              gradEnd: g1,
                              imageUrl: item['image_url']?.toString() ?? '',
                              width: isMobile ? 200.0 : 280.0,
                            ),
                          );
                        },
                      ),
                    ),
                    if (_galleryList.length > 1) ...[
                      Positioned(
                        left: 6,
                        child: _floatingGalleryArrow(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => _scrollGallery(false),
                          isLeft: true,
                        ),
                      ),
                      Positioned(
                        right: 6,
                        child: _floatingGalleryArrow(
                          icon: Icons.arrow_forward_ios_rounded,
                          onTap: () => _scrollGallery(true),
                          isLeft: false,
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _galleryCard({
    required String title,
    required String subtitle,
    required Color gradStart,
    required Color gradEnd,
    required String imageUrl,
    required double width,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradStart, gradEnd],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (imageUrl.isNotEmpty) ...[
              Positioned.fill(
                child: CorsImageWidget(
                  url: ApiService.resolveImageUrl(imageUrl),
                  fit: BoxFit.cover,
                  errorWidget: const SizedBox(),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withAlpha(40),
                        Colors.transparent,
                        Colors.black.withAlpha(200),
                      ],
                      stops: const [0.0, 0.35, 1.0],
                    ),
                  ),
                ),
              ),
            ] else ...[
              // Subtle texture dots only when no photo image is uploaded
              Positioned.fill(
                child: CustomPaint(painter: _GalleryNoisePainter()),
              ),
            ],
            // Expand hover icon indicator at top right
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(90),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            // Caption at bottom only
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(140),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      subtitle,
                      style: _outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    title,
                    style: _outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.3,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 2,
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

  // ──────────────────────────────────────────────────────────────────────────
  // MERGED FOOTER & NEED HELP CONTACT
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildFooter(bool isMobile) {
    return Container(
      key: _contactKey,
      color: _kFooter,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: isMobile ? 44 : 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Upper Merged "Need Help?" Action Section ─────────────────
              Column(
                crossAxisAlignment: isMobile
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    'Need Help?',
                    style: _outfit(
                      color: Colors.white,
                      fontSize: isMobile ? 28 : 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Our team is ready to assist with any queries about CUBAG services, membership, or training.',
                    textAlign: isMobile ? TextAlign.center : TextAlign.start,
                    style: _inter(
                      color: Colors.white.withAlpha(220),
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (isMobile)
                    Column(
                      children: [
                        _footerContactCard(
                          Icons.phone_outlined,
                          'Call CUBAG',
                          '+233 30 220 2345',
                          'Mon–Fri, 8am–5pm',
                        ),
                        const SizedBox(height: 10),
                        _footerContactCard(
                          Icons.email_outlined,
                          'Email CUBAG',
                          'info@cubag.org.gh',
                          'We respond within 24 hours',
                        ),
                        const SizedBox(height: 10),
                        _footerContactCard(
                          Icons.location_on_outlined,
                          'Visit Secretariat',
                          'CUBAG House, Tema Community 1',
                          'Greater Accra, Ghana',
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _footerContactCard(
                            Icons.phone_outlined,
                            'Call CUBAG',
                            '+233 30 220 2345',
                            'Mon–Fri, 8am–5pm',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _footerContactCard(
                            Icons.email_outlined,
                            'Email CUBAG',
                            'info@cubag.org.gh',
                            'We respond within 24 hours',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _footerContactCard(
                            Icons.location_on_outlined,
                            'Visit Secretariat',
                            'CUBAG House, Tema',
                            'Community 1, Greater Accra',
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 48),
              Divider(color: Colors.white.withAlpha(35), height: 1),
              const SizedBox(height: 40),

              // ── Middle Navigation & Information Columns ──────────────────
              isMobile
                  ? _buildMobileFooterAccordion()
                  : _buildDesktopFooterColumns(),

              const SizedBox(height: 40),
              Divider(color: Colors.white.withAlpha(35), height: 1),
              const SizedBox(height: 24),

              // ── Bottom Copyright Bar ─────────────────────────────────────
              Text(
                '© ${DateTime.now().year} Customs Brokers Association of Ghana (CUBAG). All rights reserved.',
                style: _inter(color: Colors.white.withAlpha(200), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerContactCard(
    IconData icon,
    String label,
    String value,
    String subtext,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _kAccent.withAlpha(35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: _kAccent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: _outfit(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: _inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtext,
                  style: _inter(
                    color: Colors.white.withAlpha(190),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopFooterColumns() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand & About
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const AppLogo(size: 32, borderRadius: 8),
                  const SizedBox(width: 10),
                  Text(
                    'CUBAG',
                    style: _outfit(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Customs Brokers Association of Ghana',
                style: _outfit(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Dedicated to digitizing, validating, and accelerating the clearing and forwarding trade ecosystem in the Republic of Ghana.',
                style: _inter(
                  color: Colors.white.withAlpha(210),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 48),
        // Quick Links
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _footerColTitle('Quick Links'),
              const SizedBox(height: 16),
              _footerLink(
                'Find A Licensed Broker (Clearing Agent/Forwarder)',
                () => _scrollTo(_servicesKey),
              ),
              _footerLink(
                'Register A Course',
                () => context.go('/guest-services/cti_training'),
              ),
              _footerLink(
                'Complaints & Tracking',
                () => context.go('/complaints'),
              ),
              _footerLink('Become a Member', () => context.go('/register')),
              _footerLink('Renew Membership', () => context.go('/login')),
              _footerLink('Member Directory', () => _scrollTo(_directoryKey)),
            ],
          ),
        ),
        const SizedBox(width: 48),
        // Secretariat & Office
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _footerColTitle('Secretariat'),
              const SizedBox(height: 16),
              _footerLink('+233 30 220 2345', () {}),
              _footerLink('info@cubag.org.gh', () {}),
              _footerLink('CUBAG House, Tema Community 1', () {}),
              _footerLink('Member Login', () => context.go('/login')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileFooterAccordion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerAccordion(
          'About CUBAG',
          _footerAboutExpanded,
          () => setState(() => _footerAboutExpanded = !_footerAboutExpanded),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              'Customs Brokers Association of Ghana (CUBAG) is dedicated to digitizing, validating, and accelerating the clearing and forwarding trade ecosystem in the Republic of Ghana.',
              textAlign: TextAlign.left,
              style: _inter(
                color: Colors.white.withAlpha(220),
                fontSize: 15,
                height: 1.6,
              ),
            ),
          ),
        ),
        _footerAccordion(
          'Quick Links',
          _footerLinksExpanded,
          () => setState(() => _footerLinksExpanded = !_footerLinksExpanded),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _footerLink(
                'Find a Clearing Agent',
                () => _scrollTo(_servicesKey),
              ),
              _footerLink(
                'CTI Short Courses',
                () => context.go('/guest-services/cti_training'),
              ),
              _footerLink('Become a Member', () => context.go('/register')),
              _footerLink('Member Directory', () => _scrollTo(_directoryKey)),
              _footerLink('Member Login', () => context.go('/login')),
            ],
          ),
        ),
        _footerAccordion(
          'Secretariat & Office',
          _footerContactExpanded,
          () =>
              setState(() => _footerContactExpanded = !_footerContactExpanded),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _footerLink('Phone: +233 30 220 2345', () {}),
              _footerLink('Email: info@cubag.org.gh', () {}),
              _footerLink('Office: CUBAG House, Tema Community 1', () {}),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footerAccordion(
    String title,
    bool isExpanded,
    VoidCallback onToggle, {
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: _outfit(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  color: Colors.white.withAlpha(200),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) Align(alignment: Alignment.centerLeft, child: child),
        Divider(color: Colors.white.withAlpha(25), height: 1),
      ],
    );
  }

  Widget _footerColTitle(String t) => Text(
    t.toUpperCase(),
    textAlign: TextAlign.left,
    style: _outfit(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
    ),
  );

  Widget _footerLink(String text, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        child: Text(
          text,
          textAlign: TextAlign.left,
          style: _inter(
            color: Colors.white.withAlpha(230),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ),
  );

  // ──────────────────────────────────────────────────────────────────────────
  // SHARED HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Segmented pill control — brown bg / white text when active
  Widget _segmentedControl({
    required List<String> tabs,
    required int active,
    required Function(int) onSelect,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: tabs.asMap().entries.map((e) {
          final sel = e.key == active;
          return GestureDetector(
            onTap: () => onSelect(e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? _kBrown : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                e.value,
                style: _outfit(
                  fontSize: 15,
                  fontWeight: sel ? FontWeight.bold : FontWeight.w600,
                  color: sel ? Colors.white : _kMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Orange arrow text CTA — used as section trailing action links
  Widget _textCta(String label, VoidCallback onTap) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: _kBrown,
      padding: EdgeInsets.zero,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: _outfit(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: _kBrown,
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.arrow_forward_rounded, size: 14, color: _kBrown),
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTERS
// ────────────────────────────────────────────────────────────────────────────

/// Subtle diagonal port/route-inspired line pattern at ~4% opacity
class _SubtleRoutePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6B3E26).withAlpha(10)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    const spacing = 44.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SubtleRoutePatternPainter old) => false;
}

/// Very subtle noise texture for gallery photo cards
class _GalleryNoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(7)
      ..style = PaintingStyle.fill;
    final r = math.Random(42); // fixed seed for deterministic pattern
    for (int i = 0; i < 60; i++) {
      canvas.drawCircle(
        Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
        r.nextDouble() * 2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GalleryNoisePainter old) => false;
}

/// Interactive Full Updates Modal
class _AllUpdatesDialog extends StatefulWidget {
  final int initialTab;
  final List<dynamic> portBulletins;
  final List<dynamic> newsArticles;

  const _AllUpdatesDialog({
    required this.initialTab,
    required this.portBulletins,
    required this.newsArticles,
  });

  @override
  State<_AllUpdatesDialog> createState() => _AllUpdatesDialogState();
}

class _AllUpdatesDialogState extends State<_AllUpdatesDialog> {
  late int _tab;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    // Process bulletins
    final allBulletins = widget.portBulletins
        .map(
          (pb) => {
            'port': pb['port_name']?.toString() ?? 'Port Terminal',
            'code': pb['code']?.toString() ?? 'GHA',
            'notice': pb['notice']?.toString() ?? '',
            'date': 'Live Notice',
            'status': pb['status']?.toString() ?? 'Operational',
            'status_color': pb['status_color'] != null
                ? Color(
                    int.parse(
                      pb['status_color'].toString().replaceAll('#', '0xFF'),
                    ),
                  )
                : const Color(0xFF2E7D32),
          },
        )
        .toList();

    final filteredBulletins = _query.isEmpty
        ? allBulletins
        : allBulletins.where((b) {
            final q = _query.toLowerCase();
            final port = (b['port']?.toString() ?? '').toLowerCase();
            final code = (b['code']?.toString() ?? '').toLowerCase();
            final notice = (b['notice']?.toString() ?? '').toLowerCase();
            final status = (b['status']?.toString() ?? '').toLowerCase();
            return port.contains(q) ||
                code.contains(q) ||
                notice.contains(q) ||
                status.contains(q);
          }).toList();

    // Process articles
    final allArticles = widget.newsArticles.isNotEmpty
        ? widget.newsArticles
              .map(
                (a) => {
                  'title': a['title']?.toString() ?? '',
                  'summary':
                      a['summary']?.toString() ??
                      a['description']?.toString() ??
                      '',
                  'source': a['source']?.toString() ?? 'CUBAG News',
                  'date': a['pubDate']?.toString() ?? 'Recent',
                },
              )
              .toList()
        : [
            {
              'title': 'Ghana Revenue Authority Launches ICUMS 2.0 Automation',
              'source': 'GRA Customs Circular',
              'date': '17 Aug 2026',
              'summary':
                  'New customs clearance upgrades implemented at Tema Port for faster ICUMS processing.',
            },
            {
              'title': 'GPHA Announces Port Fee Tariff Review for Q3 2026',
              'source': 'GPHA Maritime',
              'date': '16 Aug 2026',
              'summary':
                  'GPHA updates vessel handling tariffs across Tema and Takoradi port terminals.',
            },
            {
              'title':
                  'West Africa Maritime Trade Corridors Record 8.5% Growth',
              'source': 'FreightWaves',
              'date': '15 Aug 2026',
              'summary':
                  'Container throughput in agro-exports and raw goods sets record highs for the region.',
            },
          ];

    final filteredArticles = _query.isEmpty
        ? allArticles
        : allArticles.where((a) {
            final q = _query.toLowerCase();
            final title = (a['title']?.toString() ?? '').toLowerCase();
            final summary = (a['summary']?.toString() ?? '').toLowerCase();
            final source = (a['source']?.toString() ?? '').toLowerCase();
            return title.contains(q) ||
                summary.contains(q) ||
                source.contains(q);
          }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
          child: Container(
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(50),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: _kCardBg,
                    border: Border(bottom: BorderSide(color: _kBorder)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kBrown.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.feed_rounded,
                          color: _kBrown,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Industry & Port Updates',
                              style: _outfit(
                                color: _kText,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Real-time maritime news and Ghanaian port bulletins',
                              style: _inter(color: _kMuted, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: _kText,
                          size: 22,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Search & Filter Tabs bar
                Container(
                  color: _kCream,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Column(
                    children: [
                      // Search Input
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kCardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorder),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (val) =>
                              setState(() => _query = val.trim()),
                          style: _inter(fontSize: 15, color: _kText),
                          decoration: InputDecoration(
                            hintText: 'Search updates, ports, keywords...',
                            hintStyle: _inter(fontSize: 15, color: _kMuted),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: _kBrown,
                            ),
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear_rounded,
                                      size: 18,
                                      color: _kMuted,
                                    ),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _query = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Tabs
                      Row(
                        children: [
                          _tabPill(
                            'Port Bulletins (${filteredBulletins.length})',
                            0,
                            Icons.directions_boat_outlined,
                          ),
                          const SizedBox(width: 8),
                          _tabPill(
                            'Maritime News (${filteredArticles.length})',
                            1,
                            Icons.article_outlined,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Content list
                Expanded(
                  child: _tab == 0
                      ? (filteredBulletins.isEmpty
                            ? _buildEmptyState(
                                'No port bulletins matching your search.',
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(20),
                                itemCount: filteredBulletins.length,
                                separatorBuilder: (ctx, i) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (ctx, i) {
                                  final pb = filteredBulletins[i];
                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: _kCream,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: _kBorder),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: _kBrown.withAlpha(20),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.directions_boat_rounded,
                                                size: 16,
                                                color: _kBrown,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                '${pb['port']} (${pb['code']})',
                                                style: _outfit(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kText,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color:
                                                    (pb['status_color']
                                                            as Color)
                                                        .withAlpha(25),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                pb['status']?.toString() ?? '',
                                                style: _outfit(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      (pb['status_color']
                                                          as Color?) ??
                                                      _kAccent,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          pb['notice']?.toString() ?? '',
                                          style: _inter(
                                            fontSize: 15,
                                            color: _kText,
                                            height: 1.5,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Official Notice  ·  ${pb['date']}',
                                          style: _inter(
                                            fontSize: 13,
                                            color: _kMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ))
                      : (filteredArticles.isEmpty
                            ? _buildEmptyState(
                                'No articles matching your search.',
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(20),
                                itemCount: filteredArticles.length,
                                separatorBuilder: (ctx, i) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (ctx, i) {
                                  final a = filteredArticles[i];
                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: _kCream,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: _kBorder),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: _kAccent.withAlpha(25),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                Icons.article_rounded,
                                                size: 16,
                                                color: _kAccent,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                a['title']!,
                                                style: _outfit(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kText,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          a['summary']!,
                                          style: _inter(
                                            fontSize: 15,
                                            color: _kText,
                                            height: 1.5,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${a['source']}  ·  ${a['date']}',
                                          style: _inter(
                                            fontSize: 13,
                                            color: _kMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabPill(String label, int index, IconData icon) {
    final isSelected = _tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kBrown : _kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? _kBrown : _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : _kBrown),
            const SizedBox(width: 6),
            Text(
              label,
              style: _outfit(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : _kBrown,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 42,
              color: _kMuted.withAlpha(120),
            ),
            const SizedBox(height: 12),
            Text(msg, style: _inter(fontSize: 15, color: _kMuted)),
          ],
        ),
      ),
    );
  }
}

/// Interactive Full Events & Meetings Catalog Modal
class _AllEventsDialog extends StatefulWidget {
  final int initialTab;
  final List<dynamic> eventsList;
  final List<dynamic> meetingsList;

  const _AllEventsDialog({
    required this.initialTab,
    required this.eventsList,
    required this.meetingsList,
  });

  @override
  State<_AllEventsDialog> createState() => _AllEventsDialogState();
}

class _AllEventsDialogState extends State<_AllEventsDialog> {
  late int _tab;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static String _monthName(String m) {
    switch (m) {
      case '01':
        return 'Jan';
      case '02':
        return 'Feb';
      case '03':
        return 'Mar';
      case '04':
        return 'Apr';
      case '05':
        return 'May';
      case '06':
        return 'Jun';
      case '07':
        return 'Jul';
      case '08':
        return 'Aug';
      case '09':
        return 'Sep';
      case '10':
        return 'Oct';
      case '11':
        return 'Nov';
      case '12':
        return 'Dec';
      default:
        return 'Aug';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    final allEvents = widget.eventsList.map((e) {
      String rawDate = e['date']?.toString() ?? '2026-08-24';
      String day = rawDate;
      String year = '2026';
      if (rawDate.contains('-')) {
        final parts = rawDate.split('-');
        if (parts.length >= 3) {
          year = parts[0];
          day = '${parts[2]} ${_monthName(parts[1])}';
        }
      }
      return {
        'title': e['title']?.toString() ?? '',
        'day': day,
        'year': year,
        'time': e['time']?.toString() ?? '10:00 AM',
        'location': e['location']?.toString() ?? 'Accra',
        'description': e['description']?.toString() ?? '',
      };
    }).toList();

    final filteredEvents = _query.isEmpty
        ? allEvents
        : allEvents.where((e) {
            final q = _query.toLowerCase();
            final title = (e['title']?.toString() ?? '').toLowerCase();
            final location = (e['location']?.toString() ?? '').toLowerCase();
            final desc = (e['description']?.toString() ?? '').toLowerCase();
            return title.contains(q) ||
                location.contains(q) ||
                desc.contains(q);
          }).toList();

    final allMeetings = widget.meetingsList.map((m) {
      String rawDate = m['date']?.toString() ?? '2026-08-28';
      String day = rawDate;
      String year = '2026';
      if (rawDate.contains('-')) {
        final parts = rawDate.split('-');
        if (parts.length >= 3) {
          year = parts[0];
          day = '${parts[2]} ${_monthName(parts[1])}';
        }
      }
      return {
        'title': m['title']?.toString() ?? '',
        'day': day,
        'year': year,
        'time': m['time']?.toString() ?? '10:00 AM',
        'location': m['location']?.toString() ?? 'Accra',
        'description': m['description']?.toString() ?? '',
      };
    }).toList();

    final filteredMeetings = _query.isEmpty
        ? allMeetings
        : allMeetings.where((m) {
            final q = _query.toLowerCase();
            final title = (m['title']?.toString() ?? '').toLowerCase();
            final location = (m['location']?.toString() ?? '').toLowerCase();
            final desc = (m['description']?.toString() ?? '').toLowerCase();
            return title.contains(q) ||
                location.contains(q) ||
                desc.contains(q);
          }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
          child: Container(
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(50),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: _kCardBg,
                    border: Border(bottom: BorderSide(color: _kBorder)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kAccent.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.event_note_rounded,
                          color: _kAccent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Events & Scheduled Meetings',
                              style: _outfit(
                                color: _kText,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'All upcoming CUBAG events, conferences, and executive meetings',
                              style: _inter(color: _kMuted, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: _kText,
                          size: 22,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Search & Filter Tabs bar
                Container(
                  color: _kCream,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Column(
                    children: [
                      // Search Input
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: _kCardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorder),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (val) =>
                              setState(() => _query = val.trim()),
                          style: _inter(fontSize: 15, color: _kText),
                          decoration: InputDecoration(
                            hintText: 'Search events, meetings, locations...',
                            hintStyle: _inter(fontSize: 15, color: _kMuted),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: _kBrown,
                            ),
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear_rounded,
                                      size: 18,
                                      color: _kMuted,
                                    ),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _query = '');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Tabs
                      Row(
                        children: [
                          _tabPill(
                            'All Events (${filteredEvents.length})',
                            0,
                            Icons.event_rounded,
                          ),
                          const SizedBox(width: 8),
                          _tabPill(
                            'Official Meetings (${filteredMeetings.length})',
                            1,
                            Icons.groups_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Content list
                Expanded(
                  child: _tab == 0
                      ? (filteredEvents.isEmpty
                            ? _buildEmptyState(
                                'No upcoming events matching your search.',
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(20),
                                itemCount: filteredEvents.length,
                                separatorBuilder: (ctx, i) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (ctx, i) {
                                  final e = filteredEvents[i];
                                  return _buildDetailCard(
                                    day: e['day']!,
                                    year: e['year']!,
                                    title: e['title']!,
                                    time: e['time']!,
                                    location: e['location']!,
                                    description: e['description']!,
                                    badge: 'Association Event',
                                  );
                                },
                              ))
                      : (filteredMeetings.isEmpty
                            ? _buildEmptyState(
                                'No executive meetings matching your search.',
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(20),
                                itemCount: filteredMeetings.length,
                                separatorBuilder: (ctx, i) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (ctx, i) {
                                  final m = filteredMeetings[i];
                                  return _buildDetailCard(
                                    day: m['day']!,
                                    year: m['year']!,
                                    title: m['title']!,
                                    time: m['time']!,
                                    location: m['location']!,
                                    description: m['description']!,
                                    badge: 'Official Meeting',
                                  );
                                },
                              )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailCard({
    required String day,
    required String year,
    required String title,
    required String time,
    required String location,
    required String description,
    required String badge,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _kAccent.withAlpha(22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  day,
                  textAlign: TextAlign.center,
                  style: _outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _kAccent,
                  ),
                ),
                Text(
                  year,
                  style: _outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _kAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: _outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _kText,
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
                        color: _kBrown.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        badge,
                        style: _outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _kBrown,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.schedule_outlined, size: 14, color: _kMuted),
                    const SizedBox(width: 4),
                    Text(time, style: _inter(fontSize: 14, color: _kMuted)),
                    const SizedBox(width: 12),
                    Icon(Icons.location_on_outlined, size: 14, color: _kMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: _inter(fontSize: 14, color: _kMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: _inter(fontSize: 15, color: _kText, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabPill(String label, int index, IconData icon) {
    final isSelected = _tab == index;
    return InkWell(
      onTap: () => setState(() => _tab = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _kBrown : _kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? _kBrown : _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : _kBrown),
            const SizedBox(width: 6),
            Text(
              label,
              style: _outfit(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : _kBrown,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_rounded,
              size: 42,
              color: _kMuted.withAlpha(120),
            ),
            const SizedBox(height: 12),
            Text(msg, style: _inter(fontSize: 15, color: _kMuted)),
          ],
        ),
      ),
    );
  }
}

/// Interactive Full CTI Short Courses Catalog Modal
class _AllCoursesDialog extends StatefulWidget {
  final List<dynamic> coursesList;

  const _AllCoursesDialog({required this.coursesList});

  @override
  State<_AllCoursesDialog> createState() => _AllCoursesDialogState();
}

class _AllCoursesDialogState extends State<_AllCoursesDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    final allCourses = widget.coursesList.isNotEmpty
        ? widget.coursesList
              .map(
                (c) => {
                  'title': c['title']?.toString() ?? '',
                  'code': c['code']?.toString() ?? 'CTI',
                  'duration': c['duration']?.toString() ?? '4 Weeks',
                  'mode': c['mode']?.toString() ?? 'Hybrid',
                  'start_date':
                      c['start_date']?.toString() ??
                      c['date']?.toString() ??
                      'Upcoming',
                  'fee': c['fee']?.toString() ?? 'GHS 1,500',
                  'description':
                      c['description']?.toString() ??
                      'Professional certification covering customs documentation, tariff classification, single window compliance, and international freight forwarding standards.',
                },
              )
              .toList()
        : [
            {
              'title': 'Customs Valuation & HS Tariff Classification',
              'code': 'CTI-VAL',
              'duration': '4 Weeks',
              'mode': 'Hybrid',
              'start_date': '15 Sep 2026',
              'fee': 'GHS 1,800',
              'description':
                  'Master WTO valuation rules, harmonized system codes, rules of origin, and duty computation under ICUMS 2.0.',
            },
            {
              'title': 'Port Logistics & Multimodal Freight Forwarding',
              'code': 'CTI-LOG',
              'duration': '3 Weeks',
              'mode': 'In-Person',
              'start_date': '22 Sep 2026',
              'fee': 'GHS 1,500',
              'description':
                  'Comprehensive shipping container management, port terminal clearance procedures, and Incoterms 2020.',
            },
            {
              'title': 'Dangerous Goods Handling & Safety (IMDG Code)',
              'code': 'CTI-IMDG',
              'duration': '2 Days',
              'mode': 'Executive Workshop',
              'start_date': '05 Oct 2026',
              'fee': 'GHS 1,200',
              'description':
                  'Certified maritime safety standards for hazardous cargo storage, declaration, packaging, and transport.',
            },
            {
              'title': 'ICUMS Advanced Declarations & Dispute Resolution',
              'code': 'CTI-ICUMS',
              'duration': '1 Week',
              'mode': 'Online',
              'start_date': '12 Oct 2026',
              'fee': 'GHS 950',
              'description':
                  'Practical workflow training on handling post-clearance audits, amendment declarations, and customs dispute protocols.',
            },
          ];

    final filteredCourses = _query.isEmpty
        ? allCourses
        : allCourses.where((c) {
            final q = _query.toLowerCase();
            final title = (c['title']?.toString() ?? '').toLowerCase();
            final code = (c['code']?.toString() ?? '').toLowerCase();
            final desc = (c['description']?.toString() ?? '').toLowerCase();
            final mode = (c['mode']?.toString() ?? '').toLowerCase();
            return title.contains(q) ||
                code.contains(q) ||
                desc.contains(q) ||
                mode.contains(q);
          }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 750),
          child: Container(
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(50),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Modal Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: _kCardBg,
                    border: Border(bottom: BorderSide(color: _kBorder)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kBrown.withAlpha(20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.school_rounded,
                          color: _kBrown,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CTI Short Courses & Training',
                              style: _outfit(
                                color: _kText,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Professional development courses for customs brokers & trade practitioners',
                              style: _inter(color: _kMuted, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: _kText,
                          size: 22,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Search Bar
                Container(
                  color: _kCream,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorder),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (val) => setState(() => _query = val.trim()),
                      style: _inter(fontSize: 15, color: _kText),
                      decoration: InputDecoration(
                        hintText:
                            'Search courses by title, topic, or keyword...',
                        hintStyle: _inter(fontSize: 15, color: _kMuted),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: _kBrown,
                        ),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.clear_rounded,
                                  size: 18,
                                  color: _kMuted,
                                ),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),

                // Content list
                Expanded(
                  child: filteredCourses.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.school_outlined,
                                  size: 42,
                                  color: _kMuted.withAlpha(120),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No courses found matching your search.',
                                  style: _inter(fontSize: 15, color: _kMuted),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: filteredCourses.length,
                          separatorBuilder: (ctx, i) =>
                              const SizedBox(height: 14),
                          itemBuilder: (ctx, i) {
                            final c = filteredCourses[i];
                            return Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: _kCream,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _kBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: _kBrown.withAlpha(18),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.menu_book_rounded,
                                          size: 20,
                                          color: _kBrown,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    c['title']!,
                                                    style: _outfit(
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _kText,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: _kAccent.withAlpha(
                                                      25,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    c['fee']!,
                                                    style: _outfit(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: _kAccent,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 12,
                                              runSpacing: 6,
                                              children: [
                                                _dialogMeta(
                                                  Icons.calendar_today_outlined,
                                                  'Starts: ${c['start_date']}',
                                                ),
                                                _dialogMeta(
                                                  Icons.schedule_outlined,
                                                  'Duration: ${c['duration']}',
                                                ),
                                                _dialogMeta(
                                                  Icons
                                                      .cast_for_education_rounded,
                                                  'Mode: ${c['mode']}',
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              c['description']!,
                                              style: _inter(
                                                fontSize: 15,
                                                color: _kText,
                                                height: 1.45,
                                              ),
                                            ),
                                            const SizedBox(height: 14),
                                            SizedBox(
                                              height: 38,
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                  final courseTitle =
                                                      (c['title'] ?? '')
                                                          .toString()
                                                          .trim();
                                                  final uri =
                                                      courseTitle.isNotEmpty
                                                      ? '/guest-services/cti_training?course=${Uri.encodeComponent(courseTitle)}'
                                                      : '/guest-services/cti_training';
                                                  context.go(uri);
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: _kAccent,
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 18,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                                child: Text(
                                                  'Register for Course',
                                                  style: _outfit(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
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
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogMeta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: _kMuted),
      const SizedBox(width: 4),
      Text(text, style: _inter(fontSize: 14, color: _kMuted)),
    ],
  );
}

/// Interactive Full Accredited Customs Brokers Directory Modal
class _AllDirectoryDialog extends StatefulWidget {
  final List<dynamic> membersList;
  final String initialQuery;
  final Function(Map<String, dynamic>) onVerifyMember;

  const _AllDirectoryDialog({
    required this.membersList,
    this.initialQuery = '',
    required this.onVerifyMember,
  });

  @override
  State<_AllDirectoryDialog> createState() => _AllDirectoryDialogState();
}

class _AllDirectoryDialogState extends State<_AllDirectoryDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _selectedPort = 'all';

  static const List<String> _kPortsFilter = [
    'all',
    'Accra International Airport',
    'Aflao Border Port',
    'Elubo Border Port',
    'Paga Border Port',
    'Takoradi Port',
    'Tema Port',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      _query = widget.initialQuery;
      _searchCtrl.text = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    // Filter members in Good Standing, excluding admins & sub_admins
    final validMembers = widget.membersList.where((m) {
      final role = (m['role'] ?? '').toString().toLowerCase();
      if ([
            'admin',
            'super_admin',
            'sub_admin',
            'staff',
            'system',
          ].contains(role) ||
          m['is_admin'] == true) {
        return false;
      }
      final isGood =
          (m['is_good_standing'] == true ||
              m['good_standing'] == true ||
              [
                'active',
                'approved',
              ].contains((m['status'] ?? '').toString().toLowerCase())) &&
          ![
            'pending',
            'rejected',
            'suspended',
            'expelled',
            'inactive',
          ].contains((m['status'] ?? '').toString().toLowerCase());
      return isGood;
    }).toList();

    bool matchesPort(dynamic m, String filterPort) {
      if (filterPort == 'all' || filterPort.isEmpty) return true;
      final port = '${m['primary_port'] ?? ''} ${m['port_of_operation'] ?? ''}'
          .toLowerCase();
      final target = filterPort.toLowerCase();
      if (target.contains('tema')) return port.contains('tema');
      if (target.contains('takoradi') || target.contains('tkd')) {
        return port.contains('takoradi') || port.contains('tkd');
      }
      if (target.contains('accra') ||
          target.contains('kia') ||
          target.contains('kotoka') ||
          target.contains('airport')) {
        return port.contains('accra') ||
            port.contains('kia') ||
            port.contains('kotoka') ||
            port.contains('airport');
      }
      if (target.contains('aflao')) return port.contains('aflao');
      if (target.contains('elubo')) return port.contains('elubo');
      if (target.contains('paga')) return port.contains('paga');
      return port.contains(target) || target.contains(port);
    }

    final filtered = validMembers.where((m) {
      if (!matchesPort(m, _selectedPort)) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final name = (m['name'] ?? '').toString().toLowerCase();
        final comp = (m['company'] ?? '').toString().toLowerCase();
        final memNo = (m['membership_number'] ?? '').toString().toLowerCase();
        final licNo = (m['license_number'] ?? '').toString().toLowerCase();
        final port =
            '${m['primary_port'] ?? ''} ${m['port_of_operation'] ?? ''}'
                .toLowerCase();
        return name.contains(q) ||
            comp.contains(q) ||
            memNo.contains(q) ||
            licNo.contains(q) ||
            port.contains(q);
      }
      return true;
    }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 28,
      ),
      child: Container(
        width: 900,
        height: 720,
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(_globalIsDark ? 80 : 30),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: _kBrown,
                  border: Border(
                    bottom: BorderSide(color: _kBorder.withAlpha(80)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Accredited Customs Brokers Directory',
                            style: _outfit(
                              fontSize: isMobile ? 18 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${validMembers.length} Licensed Clearing Agents & Freight Forwarders',
                            style: _inter(
                              fontSize: 14,
                              color: Colors.white.withAlpha(200),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Search & Port Filter bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                color: _kCream,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: _kCardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorder),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v.trim()),
                        style: _inter(fontSize: 15.5, color: _kText),
                        decoration: InputDecoration(
                          hintText:
                              'Search by company, broker name, license no, or membership ID...',
                          hintStyle: _inter(fontSize: 15, color: _kMuted),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: _kBrown,
                            size: 20,
                          ),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear_rounded,
                                    size: 16,
                                    color: _kMuted,
                                  ),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Port Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _kPortsFilter.map((port) {
                          final isSelected = _selectedPort == port;
                          final label = port == 'all' ? 'All Ports' : port;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Text(label),
                              selected: isSelected,
                              selectedColor: _kAccent.withAlpha(30),
                              checkmarkColor: _kAccent,
                              labelStyle: _outfit(
                                fontSize: 13.5,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isSelected ? _kAccent : _kText,
                              ),
                              onSelected: (_) =>
                                  setState(() => _selectedPort = port),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              // Members List View
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 40,
                              color: _kMuted.withAlpha(140),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No matching customs brokers found',
                              style: _outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: _kText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Try selecting a different port station or clearing your search term.',
                              style: _inter(fontSize: 14, color: _kMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(18),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final m = filtered[i] as Map<dynamic, dynamic>;
                          final company =
                              m['company']?.toString() ??
                              m['name']?.toString() ??
                              'Accredited Broker';
                          final name = m['name']?.toString() ?? '';
                          final port =
                              m['primary_port']?.toString() ??
                              m['port_of_operation']?.toString() ??
                              'Tema Port';

                          return Container(
                            decoration: BoxDecoration(
                              color: _kCardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _kBorder),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(
                                    _globalIsDark ? 20 : 4,
                                  ),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _kBrown.withAlpha(18),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.business_outlined,
                                    color: _kBrown,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    company,
                                                    style: _outfit(
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _kText,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                const Icon(
                                                  Icons.verified_rounded,
                                                  size: 16,
                                                  color: Color(0xFF10B981),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (name.isNotEmpty &&
                                          name != company) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Lead Broker: $name',
                                          style: _inter(
                                            fontSize: 14,
                                            color: _kMuted,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          _dialogMeta(
                                            Icons.anchor_rounded,
                                            port,
                                          ),
                                          _dialogMeta(
                                            Icons.category_outlined,
                                            m['member_type']?.toString() ??
                                                'Accredited Broker',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () => widget.onVerifyMember(
                                    Map<String, dynamic>.from(m),
                                  ),
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 14,
                                  ),
                                  label: Text(
                                    'View',
                                    style: _outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _kBrown,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogMeta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: _kMuted),
      const SizedBox(width: 4),
      Text(text, style: _inter(fontSize: 13.5, color: _kMuted)),
    ],
  );
}
