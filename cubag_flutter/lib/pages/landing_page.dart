import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

// ── CUBAG Dynamic Theme System (Polished Editorial & Mobile-First) ───────────
bool get _globalIsDark => ThemeService.instance.isDark;
Color get _kBg => _globalIsDark
    ? const Color(0xFF1A0F0A)
    : const Color(0xFFFFFFFF); // clean crisp background
Color get _kCream => _globalIsDark
    ? const Color(0xFF281710)
    : const Color(0xFFF8F4F0); // warm ivory cream section contrast
Color get _kCardBg => _globalIsDark
    ? const Color(0xFF281710)
    : Colors.white; // clean card surface
Color get _kBrown => _globalIsDark
    ? const Color(0xFFFF5000)
    : const Color(0xFF6B3E26); // rich cocoa brown
Color get _kAccent => const Color(0xFFFF5000); // vibrant orange CTA accent
Color get _kText => _globalIsDark
    ? const Color(0xFFFFF8F3)
    : const Color(0xFF2B211D); // deep espresso text
Color get _kMuted => _globalIsDark
    ? const Color(0xFFC8ADA0)
    : const Color(0xFF6F625B); // muted warm slate-brown
Color get _kBorder => _globalIsDark
    ? const Color(0xFF4D2D20)
    : const Color(0xFFE8DED6); // subtle warm border
Color get _kFooter => _globalIsDark
    ? const Color(0xFF120A06)
    : const Color(0xFF2B211D); // deep espresso footer

TextStyle _outfit({
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const ['sans-serif'],
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: fontFeatures,
  );
}

TextStyle _inter({
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
  List<FontFeature>? fontFeatures,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: const ['sans-serif'],
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: fontFeatures,
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
  bool _loadingNews = true;
  List<dynamic> _portBulletins = [];
  bool _loadingBulletins = true;

  // Real-time Events & Meetings
  List<dynamic> _eventsList = [];
  List<dynamic> _meetingsList = [];
  bool _loadingEvents = true;

  // Real-time CTI Short Courses
  List<dynamic> _coursesList = [];
  bool _loadingCourses = true;

  // Real-time Public Surveys & Polls
  List<dynamic> _publicSurveys = [];
  bool _loadingSurveys = true;
  int _activeSurveyIdx = 0;
  final Map<int, String> _selectedOptionMap = {};
  final Set<int> _votedSurveyIds = {};
  final Map<int, bool> _submittingSurvey = {};
  String _guestId = '';

  // Real-time Gallery
  final ScrollController _galleryScrollCtrl = ScrollController();
  List<dynamic> _galleryList = [];
  bool _loadingGallery = true;
  Timer? _galleryAutoTimer;
  Timer? _backgroundSyncTimer;

  // Ports count
  int _portsCount = 0;

  // Segmented tab state
  int _activeUpdatesTab = 0; // 0 = Port News, 1 = Industry News
  int _activeEventsTab = 0; // 0 = Events,    1 = Meetings


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

    // Silent background auto-sync polling every 60 seconds
    _backgroundSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
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
    if (_publicSurveys.isEmpty) {
      setState(() => _loadingSurveys = true);
    }
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
    if (_newsArticles.isEmpty) {
      setState(() => _loadingNews = true);
    }
    try {
      final res = await ApiService().getPublic('news/public/feed');
      if (res is Map && res['items'] is List) {
        setState(() => _newsArticles = res['items']);
      } else if (res is List) {
        setState(() => _newsArticles = res);
      }
    } catch (_) {}
    if (mounted && _loadingNews) setState(() => _loadingNews = false);
  }

  Future<void> _fetchBulletins() async {
    if (_portBulletins.isEmpty) {
      setState(() => _loadingBulletins = true);
    }
    try {
      final res = await ApiService().getPublic('news/public/bulletins');
      if (res is Map && res['items'] is List) {
        setState(() => _portBulletins = res['items']);
      } else if (res is List) {
        setState(() => _portBulletins = res);
      }
    } catch (_) {}
    if (mounted && _loadingBulletins) setState(() => _loadingBulletins = false);
  }

  Future<void> _fetchEvents() async {
    if (_eventsList.isEmpty && _meetingsList.isEmpty) {
      setState(() => _loadingEvents = true);
    }
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
    if (mounted && _loadingEvents) setState(() => _loadingEvents = false);
  }

  Future<void> _fetchCourses() async {
    if (_coursesList.isEmpty) {
      setState(() => _loadingCourses = true);
    }
    try {
      final res = await ApiService().getPublic('events/public/courses');
      if (res is Map && res['items'] is List) {
        setState(() => _coursesList = res['items']);
      } else if (res is List) {
        setState(() => _coursesList = res);
      }
    } catch (_) {}
    if (mounted && _loadingCourses) setState(() => _loadingCourses = false);
  }

  Future<void> _fetchGallery() async {
    if (_galleryList.isEmpty) {
      setState(() => _loadingGallery = true);
    }
    try {
      final res = await ApiService().getPublic('events/public/gallery');
      if (res is Map && res['items'] is List) {
        setState(() => _galleryList = res['items']);
      } else if (res is List) {
        setState(() => _galleryList = res);
      }
    } catch (_) {}
    if (mounted) {
      if (_loadingGallery) setState(() => _loadingGallery = false);
      if (_galleryAutoTimer == null || !_galleryAutoTimer!.isActive) {
        _startGalleryAutoScroll();
      }
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
    final isMobile = size.width < 1100;

    return Scaffold(
      backgroundColor: _kBg,
      body: SelectionArea(
        child: Stack(
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
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HEADER — Clean, full-width bar (no black box behind CUBAG)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, bool isMobile) {
    final topPadding = MediaQuery.of(context).padding.top;
    final headerHeight = 72.0 + topPadding;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: headerHeight,
      padding: EdgeInsets.only(
        top: topPadding > 0 ? topPadding + 4 : 0,
        left: (isMobile ? 16 : 28) + MediaQuery.of(context).padding.left,
        right: (isMobile ? 16 : 28) + MediaQuery.of(context).padding.right,
      ),
      decoration: BoxDecoration(
        color: _scrolled
            ? (_globalIsDark
                  ? const Color(0xFF1A0F0A).withAlpha(248)
                  : Colors.white.withAlpha(248))
            : (_globalIsDark
                  ? const Color(0xFF1A0F0A).withAlpha(235)
                  : Colors.white.withAlpha(235)),
        border: Border(
          bottom: BorderSide(
            color: _scrolled ? _kBorder : _kBorder.withAlpha(110),
            width: 1,
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Row(
            children: [
              // Logo + CUBAG Brand Name (clean background, no black box)
              GestureDetector(
                onTap: () => _scrollTo(_heroKey),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Desktop navigation links — exact requested titles
              if (!isMobile) ...[
                _headerLink('Services', () => _scrollTo(_servicesKey)),
                _headerLink('Updates', () => _scrollTo(_updatesKey)),
                _headerLink('Accredited Members', () => _scrollTo(_directoryKey)),
                _headerLink('Events', () => _scrollTo(_eventsKey)),
                _headerLink('Register A Course', () => _scrollTo(_trainingKey)),
                _headerLink('Surveys & Polls', () => _scrollTo(_surveysKey)),
                _headerLink('Complaints', () => _scrollTo(_complaintsKey)),
                const SizedBox(width: 10),
              ],

              // Public Header CTAs: Sign In & Join CUBAG
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
                      style: _outfit(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: _kText,
                      ),
                    ),
                  ),
                  if (!isMobile) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => context.go('/register'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Join CUBAG',
                          style: _outfit(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
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
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _mobileMenuOpen = false),
        child: Container(
          color: Colors.black.withAlpha(120),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 320,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: _globalIsDark
                      ? const Color(0xFF1F1612)
                      : const Color(0xFFFAF6F0),
                  border: Border(
                    left: BorderSide(
                      color: _globalIsDark
                          ? const Color(0xFF3E2418)
                          : const Color(0xFFE2D6CB),
                      width: 1,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(50),
                      blurRadius: 30,
                      offset: const Offset(-8, 0),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Column(
                    children: [
                      // ── Top Bar with CUBAG mark, Ghana flag & Close Button ──
                      Container(
                        padding: EdgeInsets.only(
                          top: topPadding > 0 ? topPadding + 14 : 20,
                          bottom: 16,
                          left: 22,
                          right: 18,
                        ),
                        decoration: BoxDecoration(
                          color: _globalIsDark
                              ? const Color(0xFF170F0B)
                              : Colors.white,
                          border: Border(
                            bottom: BorderSide(
                              color: _globalIsDark
                                  ? const Color(0xFF331E14)
                                  : const Color(0xFFE8DED6),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const AppLogo(size: 34, borderRadius: 8),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'CUBAG',
                                        style: _outfit(
                                          color: _kText,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildGhanaFlagSvg(width: 18, height: 12),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'OFFICIAL ROLL & SERVICES',
                                    style: _inter(
                                      color: _kBrown,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _mobileMenuOpen = false),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: _kBrown.withAlpha(16),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                    color: _kText,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Scrollable Navigation Items ───────────────────────
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _drawerSectionLabel('PUBLIC SERVICES & ROLL'),
                              const SizedBox(height: 6),
                              _drawerLink(
                                'Services',
                                'Quick Services Desk',
                                Icons.grid_view_rounded,
                                () => _scrollTo(_servicesKey),
                              ),
                              _drawerLink(
                                'Updates',
                                'Port & Industry News',
                                Icons.article_outlined,
                                () => _scrollTo(_updatesKey),
                              ),
                              _drawerLink(
                                'Accredited Members',
                                'National Member Directory',
                                Icons.verified_user_outlined,
                                () => _scrollTo(_directoryKey),
                              ),

                              const SizedBox(height: 18),
                              _drawerSectionLabel('ACADEMY & SITTINGS'),
                              const SizedBox(height: 6),
                              _drawerLink(
                                'Events & Meetings',
                                'Assembly & Executive Sittings',
                                Icons.calendar_month_outlined,
                                () => _scrollTo(_eventsKey),
                              ),
                              _drawerLink(
                                'Register A Course',
                                'CTI Customs Training Academy',
                                Icons.school_outlined,
                                () => context.go('/guest-services/cti_training'),
                              ),

                              const SizedBox(height: 18),
                              _drawerSectionLabel('GOVERNANCE & REDRESSAL'),
                              const SizedBox(height: 6),
                              _drawerLink(
                                'Surveys & Polls',
                                'Public Stakeholder Opinions',
                                Icons.how_to_vote_outlined,
                                () => _scrollTo(_surveysKey),
                              ),
                              _drawerLink(
                                'Complaints & Tracking',
                                'Dispute Resolution Desk',
                                Icons.track_changes_rounded,
                                () => context.go('/complaints'),
                              ),
                              _drawerLink(
                                'Gallery',
                                'Documentary & Field Archive',
                                Icons.photo_library_outlined,
                                () => _scrollTo(_galleryKey),
                              ),
                              _drawerLink(
                                'Secretariat Desk',
                                'Headquarters Contact & Hours',
                                Icons.headset_mic_outlined,
                                () => _scrollTo(_contactKey),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ── Bottom Action Block (Member Session Only) ────────
                      Consumer<AuthService>(
                        builder: (context, auth, _) {
                          if (!auth.isAuthenticated) return const SizedBox.shrink();
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
                              ? 'Admin Portal'
                              : (isPending
                                    ? 'Application Documents'
                                    : 'Member Dashboard');

                          return Container(
                            padding: EdgeInsets.only(
                              left: 18,
                              right: 18,
                              top: 14,
                              bottom: bottomPadding > 0 ? bottomPadding + 12 : 20,
                            ),
                            decoration: BoxDecoration(
                              color: _globalIsDark
                                  ? const Color(0xFF170F0B)
                                  : Colors.white,
                              border: Border(
                                top: BorderSide(
                                  color: _globalIsDark
                                      ? const Color(0xFF331E14)
                                      : const Color(0xFFE8DED6),
                                ),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.dashboard_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      btnLabel,
                                      style: _outfit(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => _mobileMenuOpen = false,
                                      );
                                      context.go(targetRoute);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isPending
                                          ? _kAccent
                                          : _kBrown,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  height: 42,
                                  child: TextButton.icon(
                                    icon: const Icon(
                                      Icons.logout_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      'Sign Out',
                                      style: _outfit(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    onPressed: () async {
                                      setState(
                                        () => _mobileMenuOpen = false,
                                      );
                                      await auth.logout();
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          const Color(0xFFDC2626),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _drawerSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 2),
      child: Text(
        title,
        style: _outfit(
          color: _kAccent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _drawerLink(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _mobileMenuOpen = false);
          onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _kBrown.withAlpha(16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: _kBrown),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _outfit(
                        color: _kText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: _inter(
                        color: _kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: _kMuted.withAlpha(140),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ① HERO SECTION — Polished & Mobile-First with Vector Ghana Flag & Globe
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildGhanaFlagSvg({double width = 26, double height = 18}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black.withAlpha(28), width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        size: Size(width, height),
        painter: const _GhanaFlagVectorPainter(),
      ),
    );
  }

  Widget _buildGlobeSvg({double size = 28}) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _GlobeVectorPainter(color: _kAccent),
      ),
    );
  }

  Widget _buildHeroEyebrowBadge({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: _kBrown.withAlpha(18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kBrown.withAlpha(45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildGhanaFlagSvg(width: 20, height: 14),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'CUSTOMS BROKERS ASSOCIATION OF GHANA',
              style: _outfit(
                color: _kBrown,
                fontSize: isMobile ? 11.5 : 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(Size size, bool isMobile) {
    return Container(
      key: _heroKey,
      color: _kBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: isMobile ? 40 : 72,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: isMobile ? _buildMobileHero() : _buildDesktopHero(),
        ),
      ),
    );
  }

  Widget _buildMobileHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildHeroEyebrowBadge(isMobile: true),
        const SizedBox(height: 20),
        Text.rich(
          TextSpan(
            style: _outfit(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.24,
              letterSpacing: -0.6,
            ),
            children: [
              TextSpan(
                text: 'Connecting ',
                style: TextStyle(color: _kText),
              ),
              TextSpan(
                text: 'Customs Clearance ',
                style: TextStyle(color: _kBrown),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _buildGhanaFlagSvg(width: 26, height: 18),
                ),
              ),
              TextSpan(
                text: '\nFreight Forwarding &\n',
                style: TextStyle(color: _kText),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 2),
                  child: _buildGlobeSvg(size: 26),
                ),
              ),
              TextSpan(
                text: 'Int\'l Trade',
                style: TextStyle(color: _kAccent),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Access CUBAG services, connect with industry professionals, discover training opportunities, and stay informed about Ghana\'s customs and trade',
          textAlign: TextAlign.center,
          style: _inter(color: _kMuted, fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 28),
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
        const SizedBox(height: 12),
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
        const SizedBox(height: 28),
        _buildHeroStatsPanel(),
      ],
    );
  }

  Widget _buildDesktopHero() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left: Eyebrow + Headline + Subtitle + CTAs
        Expanded(
          flex: 7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroEyebrowBadge(isMobile: false),
              const SizedBox(height: 24),
              Text.rich(
                TextSpan(
                  style: _outfit(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    height: 1.16,
                    letterSpacing: -1.1,
                  ),
                  children: [
                    TextSpan(
                      text: 'Connecting ',
                      style: TextStyle(color: _kText),
                    ),
                    TextSpan(
                      text: 'Customs Clearance ',
                      style: TextStyle(color: _kBrown),
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _buildGhanaFlagSvg(width: 36, height: 25),
                      ),
                    ),
                    TextSpan(
                      text: '\nFreight Forwarding &\n',
                      style: TextStyle(color: _kText),
                    ),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 3),
                        child: _buildGlobeSvg(size: 36),
                      ),
                    ),
                    TextSpan(
                      text: 'Int\'l Trade',
                      style: TextStyle(color: _kAccent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Text(
                  'Access CUBAG services, connect with industry professionals, discover training opportunities, and stay informed about Ghana\'s customs and trade',
                  style: _inter(color: _kMuted, fontSize: 18, height: 1.65),
                ),
              ),
              const SizedBox(height: 34),
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
        const SizedBox(width: 48),
        // Right: Branded at-a-glance stats panel
        Expanded(flex: 5, child: _buildHeroStatsPanel()),
      ],
    );
  }

  Widget _buildHeroStatsPanel() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CUBAG at a Glance',
            style: _outfit(
              color: _kBrown,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 20),
          _statRow(Icons.people_outline_rounded, '1,200+', 'Active Members'),
          Divider(height: 24, color: _kBorder),
          _statRow(
            Icons.location_on_outlined,
            _portsCount > 0 ? '$_portsCount' : '6',
            'Port & Border Locations',
          ),
          Divider(height: 24, color: _kBorder),
          _statRow(
            Icons.school_outlined,
            _loadingCourses ? '...' : (_coursesList.isNotEmpty ? '${_coursesList.length}' : '0'),
            'CTI Courses Offered',
          ),
          Divider(height: 24, color: _kBorder),
          _statRow(
            Icons.directions_boat_outlined,
            'Live',
            'Vessel Tracking & AIS',
          ),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String value, String label) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _kBrown.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: _kBrown),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: _outfit(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: _kText,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(label, style: _inter(fontSize: 14, color: _kMuted)),
          ],
        ),
      ),
    ],
  );

  // ──────────────────────────────────────────────────────────────────────────
  // ② QUICK SERVICES SECTION — Exact 6 Services, Cleanly Aligned
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildQuickServicesSection(bool isMobile) {
    final services = [
      (
        title: 'Find An Accredited Member (Clearing Agent/Forwarder)',
        subtitle: 'Search verified members',
        icon: Icons.manage_search_rounded,
        onTap: () => _scrollTo(_directoryKey),
      ),
      (
        title: 'Complaints & Tracking',
        subtitle: 'Lodge & track grievance',
        icon: Icons.report_problem_outlined,
        onTap: () => _scrollTo(_complaintsKey),
      ),
      (
        title: 'Community Polls & Surveys',
        subtitle: 'Vote & voice your opinion',
        icon: Icons.how_to_vote_outlined,
        onTap: () => _scrollTo(_surveysKey),
      ),
      (
        title: 'Become a Member',
        subtitle: 'Join the association',
        icon: Icons.person_add_outlined,
        onTap: () => context.go('/register'),
      ),
      (
        title: 'Register A Course',
        subtitle: 'Professional CTI training',
        icon: Icons.school_outlined,
        onTap: () => context.go('/guest-services/cti_training'),
      ),
      (
        title: 'Renew Membership',
        subtitle: 'Extend your membership',
        icon: Icons.autorenew_rounded,
        onTap: () => context.go('/login'),
      ),
    ];

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
                'Find what you need - no account required.',
                style: _inter(color: _kMuted, fontSize: 16),
              ),
              const SizedBox(height: 28),

              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final int cols = width < 650 ? 1 : (width < 1050 ? 2 : 3);

                  if (cols == 1) {
                    return Column(
                      children: [
                        for (int i = 0; i < services.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _serviceCard(
                            services[i].title,
                            services[i].subtitle,
                            services[i].icon,
                            services[i].onTap,
                          ),
                        ],
                      ],
                    );
                  }

                  final List<Widget> rows = [];
                  for (int i = 0; i < services.length; i += cols) {
                    final rowItems = services.sublist(
                      i,
                      (i + cols > services.length) ? services.length : i + cols,
                    );
                    rows.add(
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int j = 0; j < rowItems.length; j++) ...[
                              if (j > 0) const SizedBox(width: 16),
                              Expanded(
                                child: _serviceCard(
                                  rowItems[j].title,
                                  rowItems[j].subtitle,
                                  rowItems[j].icon,
                                  rowItems[j].onTap,
                                ),
                              ),
                            ],
                            for (int k = 0; k < (cols - rowItems.length); k++) ...[
                              const SizedBox(width: 16),
                              const Expanded(child: SizedBox()),
                            ],
                          ],
                        ),
                      ),
                    );
                    if (i + cols < services.length) {
                      rows.add(const SizedBox(height: 16));
                    }
                  }

                  return Column(children: rows);
                },
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder, width: 1.2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _kBrown.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 24, color: _kBrown),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: _outfit(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: _kText,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: _inter(fontSize: 14, color: _kMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Get started →',
                      style: _outfit(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
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
  // ③ INDUSTRY UPDATES
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
                  Expanded(
                    child: Column(
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

              _segmentedControl(
                tabs: ['Port News', 'Industry News'],
                active: _activeUpdatesTab,
                onSelect: (i) => setState(() => _activeUpdatesTab = i),
              ),
              const SizedBox(height: 20),

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
    if (_loadingBulletins && _portBulletins.isEmpty) {
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
        padding: const EdgeInsets.all(28),
        color: _kCream,
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
            'date': 'Live Dispatch',
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
              trailingLabel: 'Read Notice →',
              onTap: () => _showAllUpdatesModal(context, initialTab: 0),
            ),
          )
          .toList(),
    );
  }

  Widget _buildIndustryNewsCards({Key? key}) {
    if (_loadingNews && _newsArticles.isEmpty) {
      return Center(
        key: const ValueKey('loading_news'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
        ),
      );
    }
    if (_newsArticles.isEmpty) {
      return Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        color: _kCream,
        child: Text(
          'No industry news updates available at this time.',
          style: _inter(color: _kMuted, fontSize: 15),
        ),
      );
    }

    final articles = _newsArticles
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
        .toList();

    return Column(
      key: key,
      children: articles
          .map(
            (a) => _updateCard(
              icon: Icons.article_outlined,
              headline: a['title']!,
              body: a['summary']!,
              meta: '${a['source']}  ·  ${a['date']}',
              trailingLabel: 'Read More →',
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
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _kCream,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _kBrown.withAlpha(18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 19, color: _kBrown),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        headline,
                        style: _outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _kText,
                          height: 1.25,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (statusLabel != null && statusLabel.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (statusColor ?? _kBrown).withAlpha(22),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          statusLabel,
                          style: _inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor ?? _kBrown,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  style: _inter(fontSize: 14.5, color: _kMuted, height: 1.55),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meta,
                        style: _inter(
                          fontSize: 13,
                          color: _kMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (trailingLabel != null)
                      Text(
                        trailingLabel,
                        style: _outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _kAccent,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ④ ACCREDITED MEMBER REGISTRY
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildMemberDirectorySection(bool isMobile) {
    final searchLedger = Container(
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2B211D).withAlpha(10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Find an Accredited Member',
            style: _outfit(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: _kText,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Search by company name, clearing agent, license number, or location.',
            style: _inter(fontSize: 14.5, color: _kMuted, height: 1.45),
          ),
          const SizedBox(height: 18),
          _buildBrokerTypeAhead(isMobile),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_directoryMembers.length} verified members available',
                style: _inter(
                  fontSize: 13.5,
                  color: _kMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              InkWell(
                onTap: () => _showAllDirectoryModal(
                  context,
                  initialQuery: _dirSearchCtrl.text.trim(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Browse Full Directory →',
                    style: _outfit(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _kAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Container(
      key: _directoryKey,
      color: _kCream,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: isMobile ? 48 : 84,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FIND AN ACCREDITED MEMBER (CLEARING AGENT/FORWARDER)',
                      style: _outfit(
                        color: _kAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Accredited Members Directory',
                      style: _outfit(
                        color: _kText,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Verify standing before entrusting cargo documents. Every firm listed holds active CUBAG accreditation.',
                      style: _inter(
                        color: _kMuted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    searchLedger,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FIND AN ACCREDITED MEMBER (CLEARING AGENT/FORWARDER)',
                              style: _outfit(
                                color: _kAccent,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Accredited Members Directory',
                              style: _outfit(
                                color: _kText,
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.9,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                'Verify standing before entrusting cargo documents. Every firm listed holds active CUBAG accreditation across Ghana.',
                                style: _inter(
                                  color: _kMuted,
                                  fontSize: 16,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(flex: 7, child: searchLedger),
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
    final port = m['primary_port']?.toString() ?? 'Main Port';
    final type = m['member_type']?.toString() ?? 'Corporate';
    final phone = m['phone']?.toString() ?? '';
    final email = m['email']?.toString() ?? '';
    final location = m['location']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.all(26),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10b981).withAlpha(24),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Verified Standing · Active Roll',
                  style: _inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF10b981),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                company,
                style: _outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: _kText,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Customs Brokers Association of Ghana (CUBAG)',
                style: _inter(fontSize: 14, color: _kMuted),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _kCream,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _modalDetailRow('Company Entity', company),
                    if (name.isNotEmpty && name != company) ...[
                      const SizedBox(height: 12),
                      _modalDetailRow('Lead Member / Contact', name),
                    ],
                    const SizedBox(height: 12),
                    _modalDetailRow('District(s)', port),
                    const SizedBox(height: 12),
                    _modalDetailRow('Member Category', type),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _modalDetailRow('Office Location', location),
                    ],
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _modalDetailRow('Direct Phone', phone),
                    ],
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _modalDetailRow('Official Email', email, isEmail: true),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBrown,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Close Record',
                    style: _outfit(fontWeight: FontWeight.bold, fontSize: 15.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrokerTypeAhead(bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<Map<String, dynamic>>(
          textEditingController: _dirSearchCtrl,
          focusNode: FocusNode(),
          optionsBuilder: (TextEditingValue textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            if (query.isEmpty) {
              return const Iterable<Map<String, dynamic>>.empty();
            }
            final matches = <Map<String, dynamic>>[];
            for (final raw in _directoryMembers) {
              if (raw is Map<String, dynamic>) {
                final name = (raw['name'] ?? '').toString().toLowerCase();
                final company = (raw['company'] ?? '').toString().toLowerCase();
                final license = (raw['license_number'] ?? '').toString().toLowerCase();
                final port = (raw['primary_port'] ?? '').toString().toLowerCase();
                final location = (raw['location'] ?? '').toString().toLowerCase();

                if (name.contains(query) ||
                    company.contains(query) ||
                    license.contains(query) ||
                    port.contains(query) ||
                    location.contains(query)) {
                  matches.add(raw);
                  if (matches.length >= 8) break;
                }
              }
            }
            return matches;
          },
          displayStringForOption: (option) =>
              option['company']?.toString() ?? option['name']?.toString() ?? '',
          onSelected: (option) {
            _showMemberVerificationModal(option);
          },
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController fieldTextEditingController,
            FocusNode fieldFocusNode,
            VoidCallback onFieldSubmitted,
          ) {
            final searchInput = Container(
              decoration: BoxDecoration(
                color: _kCream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: TextField(
                controller: fieldTextEditingController,
                focusNode: fieldFocusNode,
                onSubmitted: (query) => _showAllDirectoryModal(
                  context,
                  initialQuery: query.trim(),
                ),
                style: _inter(fontSize: isMobile ? 15 : 15.5, color: _kText),
                decoration: InputDecoration(
                  hintText: 'Search member name, company, or license...',
                  hintStyle: _inter(color: _kMuted, fontSize: isMobile ? 14 : 15),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: _kBrown,
                    size: 20,
                  ),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: fieldTextEditingController,
                    builder: (context, val, _) {
                      if (val.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                        onPressed: () => fieldTextEditingController.clear(),
                      );
                    },
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 14 : 16,
                    vertical: isMobile ? 14 : 16,
                  ),
                ),
              ),
            );

            if (isMobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchInput,
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _showAllDirectoryModal(
                        context,
                        initialQuery: fieldTextEditingController.text.trim(),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrown,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Search Members',
                        style: _outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            } else {
              return Row(
                children: [
                  Expanded(child: searchInput),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _showAllDirectoryModal(
                        context,
                        initialQuery: fieldTextEditingController.text.trim(),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrown,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 26),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Search Directory',
                        style: _outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
          },
          optionsViewBuilder: (
            BuildContext context,
            AutocompleteOnSelected<Map<String, dynamic>> onSelected,
            Iterable<Map<String, dynamic>> options,
          ) {
            final optionsList = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: _kCardBg,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 320,
                    maxWidth: isMobile ? constraints.maxWidth : constraints.maxWidth * 0.75,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorder),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: optionsList.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: _kBorder.withAlpha(80)),
                      itemBuilder: (BuildContext context, int index) {
                        final m = optionsList[index];
                        final company = m['company']?.toString() ?? m['name']?.toString() ?? 'Licensed Member';
                        final name = m['name']?.toString() ?? '';
                        final port = m['primary_port']?.toString() ?? 'Port Operations';
                        final license = m['license_number']?.toString();

                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF10b981).withAlpha(25),
                            child: const Icon(Icons.verified_rounded, color: Color(0xFF10b981), size: 18),
                          ),
                          title: Text(
                            company,
                            style: _outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: _kText,
                            ),
                          ),
                          subtitle: Text(
                            '${name.isNotEmpty ? "$name · " : ""}$port${license != null && license.isNotEmpty ? " · Lic: $license" : ""}',
                            style: _inter(fontSize: 12, color: _kMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
                          onTap: () {
                            onSelected(m);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _modalDetailRow(String label, String value, {bool isEmail = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: _inter(fontSize: 14, color: _kMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: SelectableText(
              value,
              style: _outfit(
                fontSize: isEmail ? 14.5 : 15,
                fontWeight: FontWeight.w700,
                color: _kText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ⑤ EVENTS & MEETINGS SECTION
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildEventsSection(bool isMobile) {
    final eventsFeed = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: (_loadingEvents && _eventsList.isEmpty && _meetingsList.isEmpty)
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
    );

    return Container(
      key: _eventsKey,
      color: _kBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: isMobile ? 48 : 84,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Events & Meetings',
                      style: _outfit(
                        color: _kText,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mark your calendar for upcoming CUBAG events and meetings.',
                      style: _inter(
                        color: _kMuted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _segmentedControl(
                      tabs: ['Events', 'Meetings'],
                      active: _activeEventsTab,
                      onSelect: (i) => setState(() => _activeEventsTab = i),
                    ),
                    const SizedBox(height: 18),
                    eventsFeed,
                    const SizedBox(height: 12),
                    _textCta(
                      'View all',
                      () => _showAllEventsModal(
                        context,
                        initialTab: _activeEventsTab,
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Events & Meetings',
                              style: _outfit(
                                color: _kText,
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.9,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 400),
                              child: Text(
                                'Mark your calendar for upcoming CUBAG general assemblies, industry forums, and regional chapter meetings.',
                                style: _inter(
                                  color: _kMuted,
                                  fontSize: 16,
                                  height: 1.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            _segmentedControl(
                              tabs: ['Events', 'Meetings'],
                              active: _activeEventsTab,
                              onSelect: (i) =>
                                  setState(() => _activeEventsTab = i),
                            ),
                            const SizedBox(height: 22),
                            _textCta(
                              'View all',
                              () => _showAllEventsModal(
                                context,
                                initialTab: _activeEventsTab,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(flex: 7, child: eventsFeed),
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
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _kCream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
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
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _kCream,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Text(
          'No upcoming meetings scheduled at this time.',
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _kCream,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 74,
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _kCardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    children: [
                      Text(
                        day,
                        textAlign: TextAlign.center,
                        style: _outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _kAccent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        year,
                        style: _inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: _outfit(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: _kText,
                          height: 1.25,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$time  ·  $location',
                        style: _inter(
                          fontSize: 14,
                          color: _kMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'View details →',
                        style: _outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _kBrown,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ⑥ REGISTER A COURSE (CTI TRAINING)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCtiTrainingSection(bool isMobile) {
    Widget coursesContent;
    if (_loadingCourses && _coursesList.isEmpty) {
      coursesContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _kAccent,
          ),
        ),
      );
    } else if (_coursesList.isEmpty) {
      coursesContent = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Text(
          'No CTI training courses currently open for enrolment.',
          style: _inter(color: _kMuted, fontSize: 15),
        ),
      );
    } else {
      coursesContent = Column(
        children: _coursesList
            .take(3)
            .toList()
            .asMap()
            .entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ctiCourseCard(
                  entry.value as Map<dynamic, dynamic>,
                  index: entry.key + 1,
                  onTap: () => _showAllCoursesModal(context),
                ),
              ),
            )
            .toList(),
      );
    }

    return Container(
      key: _trainingKey,
      color: _kCream,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: isMobile ? 48 : 84,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'REGISTER A COURSE',
                      style: _outfit(
                        color: _kAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Professional CTI Training',
                      style: _outfit(
                        color: _kText,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enroll in Customs Training Institute (CTI) short courses and certification programs.',
                      style: _inter(
                        color: _kMuted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    coursesContent,
                    const SizedBox(height: 10),
                    _textCta(
                      'View all courses',
                      () => _showAllCoursesModal(context),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'REGISTER A COURSE',
                              style: _outfit(
                                color: _kAccent,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Professional CTI Training',
                              style: _outfit(
                                color: _kText,
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.9,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                'Professional customs tariff, HS classification, and ICUMS declarant cohorts conducted by the Customs Training Institute (CTI).',
                                style: _inter(
                                  color: _kMuted,
                                  fontSize: 16,
                                  height: 1.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 26),
                            _textCta(
                              'View all courses',
                              () => _showAllCoursesModal(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(flex: 7, child: coursesContent),
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

  Widget _ctiCourseCard(
    Map<dynamic, dynamic> c, {
    int index = 1,
    VoidCallback? onTap,
  }) {
    final startDate =
        c['start_date']?.toString() ?? c['date']?.toString() ?? 'Upcoming';
    final durationAndMode =
        '${c['duration'] ?? '4 Weeks'} · ${c['mode'] ?? 'Hybrid'}';
    final fee = c['fee']?.toString() ?? 'GHS 1,500';

    return Material(
      color: _kCardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _kAccent.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      index.toString().padLeft(2, '0'),
                      style: _outfit(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: _kAccent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                c['title']?.toString() ?? '',
                                style: _outfit(
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w700,
                                  color: _kText,
                                  height: 1.25,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              fee,
                              style: _outfit(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: _kBrown,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$startDate  ·  $durationAndMode',
                          style: _inter(
                            fontSize: 14,
                            color: _kMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ElevatedButton(
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                'Register Now →',
                                style: _outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap:
                                  onTap ?? () => _showAllCoursesModal(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 4,
                                ),
                                child: Text(
                                  'Course Details',
                                  style: _outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _kBrown,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  // ──────────────────────────────────────────────────────────────────────────
  // ⑦ COMPLAINTS & TRACKING ORDER SECTION
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildComplaintsSection(bool isMobile) {
    return Container(
      key: _complaintsKey,
      color: _kBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: isMobile ? 48 : 84,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                Text(
                  'DISPUTE & GRIEVANCE REDRESSAL',
                  style: _outfit(
                    color: _kAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Complaints & Tracking Order',
                  style: _outfit(
                    color: _kText,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lodge an official grievance or track your existing complaint status in real time.',
                  style: _inter(color: _kMuted, fontSize: 15, height: 1.5),
                ),
                const SizedBox(height: 22),
                _buildComplaintTrackingCard(isMobile),
                const SizedBox(height: 14),
                _buildLodgeComplaintCtaCard(isMobile),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DISPUTE & GRIEVANCE REDRESSAL',
                              style: _outfit(
                                color: _kAccent,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Complaints & Tracking Order',
                              style: _outfit(
                                color: _kText,
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.9,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                'Lodge an official grievance regarding clearance delays, demurrage disputes, or member conduct — or track the live status of an existing complaint.',
                                style: _inter(
                                  color: _kMuted,
                                  fontSize: 16,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          _buildComplaintTrackingCard(isMobile),
                          const SizedBox(height: 14),
                          _buildLodgeComplaintCtaCard(isMobile),
                        ],
                      ),
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
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 26),
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Track Existing Complaint',
            style: _outfit(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: _kText,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter your tracking reference ID for live status updates.',
            style: _inter(fontSize: 14.5, color: _kMuted),
          ),
          const SizedBox(height: 16),

          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: _kCardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorder),
                      ),
                      child: TextField(
                        controller: _homeTrackCtrl,
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _homeTrackComplaint(),
                        style: _inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: _kText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. CMP-2026-92945',
                          hintStyle: _inter(
                            fontSize: 14.5,
                            color: _kMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
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
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _homeTracking ? null : _homeTrackComplaint,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBrown,
                          foregroundColor: Colors.white,
                          elevation: 0,
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
                                'Track Status',
                                style: _outfit(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _kCardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorder),
                        ),
                        child: TextField(
                          controller: _homeTrackCtrl,
                          textCapitalization: TextCapitalization.characters,
                          onSubmitted: (_) => _homeTrackComplaint(),
                          style: _inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _kText,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. CMP-2026-92945',
                            hintStyle: _inter(
                              fontSize: 15,
                              color: _kMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: _kBrown,
                              size: 20,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _homeTracking ? null : _homeTrackComplaint,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBrown,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
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
                                'Track Status',
                                style: _outfit(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
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
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _kCardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _homeTrackResult!['complaint_id']?.toString() ?? '',
                        style: _inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _kBrown,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _kAccent.withAlpha(24),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          (_homeTrackResult!['status'] ?? 'Received').toString(),
                          style: _outfit(
                            color: _kAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _homeTrackResult!['subject']?.toString() ?? '',
                    style: _outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Category: ${_homeTrackResult!['category'] ?? 'General'}',
                    style: _inter(fontSize: 14, color: _kMuted),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => context.go(
                      '/complaints/track/${_homeTrackResult!['complaint_id']}',
                    ),
                    child: Text(
                      'Open Full Complaint Timeline →',
                      style: _outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kBrown,
                      ),
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

  Widget _buildLodgeComplaintCtaCard(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 26),
      decoration: BoxDecoration(
        color: _kFooter,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lodge a New Complaint',
            style: _outfit(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Submit an official grievance for direct investigation by the CUBAG Secretariat.',
            style: _inter(
              fontSize: 14.5,
              color: Colors.white.withAlpha(200),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 46,
            width: isMobile ? double.infinity : null,
            child: ElevatedButton(
              onPressed: () => context.go('/complaints'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Lodge Official Complaint →',
                style: _outfit(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
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
      color: _kCardBg,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 18, color: _kText),
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
                  color: _kCardBg,
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
                        color: _kCardBg,
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
                                  color: _kAccent.withAlpha(25),
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
                                  style: _inter(
                                    fontSize: 14,
                                    color: _kMuted,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close_sharp,
                                size: 22,
                                color: _kText,
                              ),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      ),

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
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.chevron_left_sharp,
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
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.chevron_right_sharp,
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
                        color: _kCardBg,
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
  // PUBLIC SURVEYS & POLLS SECTION
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildSurveysSection(bool isMobile) {
    final surveyBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _activeSurveyIdx = idx),
                    child: Container(
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
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? Colors.transparent : _kBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            displayTitle,
                            style: _outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: isSelected ? Colors.white : _kText,
                            ),
                          ),
                          if (isVoted) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_rounded,
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
          const SizedBox(height: 12),
        ],
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _loadingSurveys && _publicSurveys.isEmpty
              ? Center(
                  key: const ValueKey('loading_surveys'),
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _kAccent,
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
    );

    return Container(
      key: _surveysKey,
      color: _kCream,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: isMobile ? 48 : 84,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMMUNITY OPINION & POLLS',
                      style: _outfit(
                        color: _kAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Have Your Say — Public Surveys',
                      style: _outfit(
                        color: _kText,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Vote and voice your opinion on customs clearance, freight forwarding, and trade operations.',
                      style: _inter(
                        color: _kMuted,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    surveyBody,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'COMMUNITY OPINION & POLLS',
                              style: _outfit(
                                color: _kAccent,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Have Your Say — Public Surveys',
                              style: _outfit(
                                color: _kText,
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                                letterSpacing: -0.9,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                'Open to importers, exporters, and accredited members. Vote and voice your opinion on port operations, ICUMS workflows, and trade policy.',
                                style: _inter(
                                  color: _kMuted,
                                  fontSize: 16,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(flex: 7, child: surveyBody),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildNoPublicSurveysCard(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 24 : 34),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No Active Surveys Open',
            style: _outfit(
              fontWeight: FontWeight.w700,
              fontSize: isMobile ? 19 : 21,
              color: _kText,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              'New community polls and stakeholder surveys are published here when opened by the CUBAG Secretariat.',
              style: _inter(fontSize: 15, color: _kMuted, height: 1.5),
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverImage != null && coverImage.isNotEmpty)
            CachedNetworkImage(
              imageUrl: coverImage,
              width: double.infinity,
              height: isMobile ? 150 : 190,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),

          Padding(
            padding: EdgeInsets.all(isMobile ? 20 : 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _kBrown.withAlpha(18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        type,
                        style: _inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _kBrown,
                        ),
                      ),
                    ),
                    if (deadline != null && deadline.isNotEmpty)
                      Text(
                        'Closes $deadline',
                        style: _inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _kMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                Text(
                  title,
                  style: _outfit(
                    fontWeight: FontWeight.w800,
                    fontSize: isMobile ? 21 : 25,
                    color: _kText,
                    height: 1.18,
                    letterSpacing: -0.4,
                  ),
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    desc,
                    style: _inter(
                      fontSize: isMobile ? 15 : 16,
                      color: _kMuted,
                      height: 1.55,
                    ),
                  ),
                ],
                const SizedBox(height: 22),

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
          'Select your response:',
          style: _outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _kText,
          ),
        ),
        const SizedBox(height: 14),

        if (isYesNo)
          Row(
            children: [
              Expanded(
                child: _buildVoteChoiceTile(
                  surveyId: surveyId,
                  optionName: 'Yes',
                  icon: Icons.check_rounded,
                  isSelected: selectedOption?.toLowerCase() == 'yes',
                  activeColor: const Color(0xFF10b981),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildVoteChoiceTile(
                  surveyId: surveyId,
                  optionName: 'No',
                  icon: Icons.close_rounded,
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
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      setState(() => _selectedOptionMap[surveyId] = name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (_globalIsDark
                                ? const Color(0xFF332018)
                                : const Color(0xFFEFE6DC))
                          : _kCream,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? _kAccent : _kBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (photo != null && photo.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: photo,
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Container(
                                width: 38,
                                height: 38,
                                color: _kAccent.withValues(alpha: 0.2),
                                alignment: Alignment.center,
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
                              fontSize: 16,
                              color: _kText,
                            ),
                          ),
                        ),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isSelected ? _kAccent : _kCardBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? _kAccent : _kBorder,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
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

        const SizedBox(height: 20),

        SizedBox(
          height: 48,
          width: isMobile ? double.infinity : 240,
          child: ElevatedButton(
            onPressed: isSubmitting ? null : () => _submitGuestVote(survey),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              isSubmitting ? 'Submitting Vote...' : 'Submit Vote →',
              style: _outfit(fontWeight: FontWeight.w700, fontSize: 15.5),
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
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selectedOptionMap[surveyId] = optionName),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: _globalIsDark ? 0.22 : 0.14)
              : _kCream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : _kBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: isSelected ? activeColor : _kMuted),
            const SizedBox(width: 8),
            Text(
              optionName,
              style: _outfit(
                fontSize: 17,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
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
        color: _kCream,
        borderRadius: BorderRadius.circular(12),
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
                iconSize: 34,
                onPressed: () =>
                    setState(() => _selectedOptionMap[surveyId] = '$starNum'),
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_border_rounded,
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
                ? '$currentVal / 5 rating selected'
                : 'Select 1 to 5 stars',
            style: _inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: currentVal > 0 ? _kText : _kMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
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
        color: _kCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vote Recorded · Live Results ($totalVotes total)',
            style: _outfit(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF10b981),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),

          if (avgStars > 0 && options.isEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  avgStars.toStringAsFixed(1),
                  style: _outfit(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: _kText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '/ 5.0 average ($totalVotes ratings)',
                  style: _inter(
                    fontSize: 14.5,
                    color: _kMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
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
                        Expanded(
                          child: Text(
                            optName,
                            style: _outfit(
                              fontSize: 15.5,
                              fontWeight: isLeader
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: _kText,
                            ),
                          ),
                        ),
                        Text(
                          '$count  ·  ${(pct * 100).toStringAsFixed(1)}%',
                          style: _inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isLeader ? _kAccent : _kMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: barPct.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: _kCardBg,
                        color: isLeader
                            ? _kAccent
                            : _kBrown.withValues(alpha: 0.45),
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

  // ──────────────────────────────────────────────────────────────────────────
  // ⑧ GALLERY SECTION — Full Color Photographic Cards
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildGallerySection(bool isMobile) {
    return Container(
      key: _galleryKey,
      color: _kBg,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: isMobile ? 48 : 84,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gallery',
                          style: _outfit(
                            color: _kText,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Highlights from CUBAG events, training sessions, and community activities.',
                          style: _inter(color: _kMuted, fontSize: 15),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 48),
                            child: Text(
                              'Gallery',
                              style: _outfit(
                                color: _kText,
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.9,
                                height: 1.08,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 7,
                          child: Text(
                            'Highlights from CUBAG general assemblies, CTI training cohorts, and community activities.',
                            style: _inter(
                              color: _kMuted,
                              fontSize: 16,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 28),

              if (_loadingGallery && _galleryList.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kAccent,
                    ),
                  ),
                )
              else if (_galleryList.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: _kCream,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Text(
                    'No gallery photos published at this time.',
                    style: _inter(color: _kMuted, fontSize: 15),
                  ),
                )
              else
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: isMobile ? 210 : 250,
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
                            fallback: const Color(0xFF2B211D),
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
                              width: isMobile ? 230.0 : 300.0,
                            ),
                          );
                        },
                      ),
                    ),
                    if (_galleryList.length > 1) ...[
                      Positioned(
                        left: 8,
                        child: _floatingGalleryArrow(
                          icon: Icons.arrow_back_rounded,
                          onTap: () => _scrollGallery(false),
                          isLeft: true,
                        ),
                      ),
                      Positioned(
                        right: 8,
                        child: _floatingGalleryArrow(
                          icon: Icons.arrow_forward_rounded,
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
    return Container(
      width: width,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradStart, gradEnd],
        ),
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(170),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            Positioned.fill(
              child: CustomPaint(painter: _GalleryNoisePainter()),
            ),
          ],
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    subtitle,
                    style: _inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: _outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ⑨ FOOTER — Clean CUBAG Footer (No Member Sign In button at bottom)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildFooter(bool isMobile) {
    const paperOnDark = Color(0xFFF8F4F0);
    const mutedOnDark = Color(0xFFC4B6A8);

    return Container(
      key: _contactKey,
      color: _kFooter,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: isMobile ? 48 : 76,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Brand + Back to top ↑
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const AppLogo(size: 32, borderRadius: 8),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CUBAG',
                                style: _outfit(
                                  color: paperOnDark,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Customs Brokers Association of Ghana',
                                style: _inter(
                                  color: mutedOnDark,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        'Back to top ↑',
                        style: _outfit(
                          color: const Color(0xFFFF5000),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: isMobile ? 32 : 48),

              // Need Help? Contact section
              Text(
                'Need Help?',
                style: _outfit(
                  color: const Color(0xFFFF5000),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'info@cubag.org.gh',
                style: _outfit(
                  color: paperOnDark,
                  fontSize: isMobile ? 26 : 44,
                  fontWeight: FontWeight.w800,
                  letterSpacing: isMobile ? -0.6 : -1.2,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                '+233 30 220 2345',
                style: _outfit(
                  color: mutedOnDark,
                  fontSize: isMobile ? 20 : 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),

              SizedBox(height: isMobile ? 32 : 48),

              Divider(color: Colors.white.withAlpha(24), height: 1),
              const SizedBox(height: 24),

              // Bottom copyright row (no Member Sign In, no Tema/Takoradi)
              Text(
                '© ${DateTime.now().year} Customs Brokers Association of Ghana (CUBAG). All rights reserved.',
                style: _inter(
                  color: mutedOnDark,
                  fontSize: 13.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SHARED HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Pill/rounded tonal switcher — brown bg / white text when active
  Widget _segmentedControl({
    required List<String> tabs,
    required int active,
    required Function(int) onSelect,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _kCream,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: tabs.asMap().entries.map((e) {
          final sel = e.key == active;
          return GestureDetector(
            onTap: () => onSelect(e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? _kBrown : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                e.value,
                style: _outfit(
                  fontSize: 14,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                  color: sel ? Colors.white : _kMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Arrow text CTA — used as section trailing action links
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
            fontWeight: FontWeight.w700,
            color: _kBrown,
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.arrow_forward_rounded, size: 16, color: _kBrown),
      ],
    ),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTERS (GHANA FLAG SVG, GLOBE SVG, GALLERY NOISE)
// ────────────────────────────────────────────────────────────────────────────

/// Crisp vector painter for the official Republic of Ghana Flag
/// (Red #CE1126, Gold #FCD116, Green #006B3F + centered 5-pointed Black Star)
class _GhanaFlagVectorPainter extends CustomPainter {
  const _GhanaFlagVectorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stripeHeight = size.height / 3.0;

    // Top stripe: Red (#CE1126)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, stripeHeight),
      Paint()..color = const Color(0xFFCE1126),
    );

    // Middle stripe: Gold (#FCD116)
    canvas.drawRect(
      Rect.fromLTWH(0, stripeHeight, size.width, stripeHeight),
      Paint()..color = const Color(0xFFFCD116),
    );

    // Bottom stripe: Green (#006B3F)
    canvas.drawRect(
      Rect.fromLTWH(0, stripeHeight * 2, size.width, stripeHeight),
      Paint()..color = const Color(0xFF006B3F),
    );

    // Centered 5-pointed Black Star in the Gold stripe
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    final outerRadius = stripeHeight * 0.46;
    final innerRadius = outerRadius * 0.382;
    final starPath = Path();

    for (int i = 0; i < 10; i++) {
      final radius = i.isEven ? outerRadius : innerRadius;
      final angle = -math.pi / 2 + (i * math.pi / 5);
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);
      if (i == 0) {
        starPath.moveTo(x, y);
      } else {
        starPath.lineTo(x, y);
      }
    }
    starPath.close();

    canvas.drawPath(
      starPath,
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _GhanaFlagVectorPainter oldDelegate) => false;
}

/// Crisp vector painter for the International Trade Globe SVG icon
class _GlobeVectorPainter extends CustomPainter {
  final Color? color;
  const _GlobeVectorPainter({this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.44;

    // Ocean fill
    final oceanPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2EA8FF), Color(0xFF0B63CE)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, oceanPaint);

    // Continents / meridian lines in crisp white/teal
    final linePaint = Paint()
      ..color = Colors.white.withAlpha(210)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055;

    // Outer rim
    canvas.drawCircle(center, radius, linePaint);

    // Equator & tropics
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      linePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      linePaint,
    );

    // Meridian oval
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 1.05,
        height: radius * 1.92,
      ),
      linePaint,
    );

    // Latitude oval
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 1.92,
        height: radius * 0.95,
      ),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlobeVectorPainter oldDelegate) => false;
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
    final allArticles = widget.newsArticles
        .map(
          (a) => <String, String>{
            'title': a['title']?.toString() ?? '',
            'summary':
                a['summary']?.toString() ??
                a['description']?.toString() ??
                '',
            'source': a['source']?.toString() ?? 'CUBAG News',
            'date': a['pubDate']?.toString() ?? 'Recent',
          },
        )
        .toList();

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

    final allCourses = widget.coursesList
        .map(
          (c) => <String, String>{
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
        .toList();

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
                              'Professional development courses for customs practitioners & members',
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

/// Interactive Full Accredited Members Directory Modal
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
                            'Accredited Members Directory',
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
                              'Search by company, member name, license no, or membership ID...',
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
                              'No matching members found',
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
                              'Accredited Member';
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
                                          'Lead Member: $name',
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
                                                'Accredited Member',
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
