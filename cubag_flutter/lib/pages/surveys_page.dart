import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/cors_image_widget.dart';
import '../components/shimmer_loader.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kPurple = Color(0xFF8B5CF6);

class SurveysPage extends StatefulWidget {
  const SurveysPage({super.key});

  @override
  State<SurveysPage> createState() => _SurveysPageState();
}

class _SurveysPageState extends State<SurveysPage> {
  bool _loading = true;
  List<dynamic> _surveys = [];
  String _tab = 'active'; // 'active' or 'past'
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  Map<String, dynamic>? _answering;
  String _selected = '';
  bool _submitting = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = v.trim());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!_loading) setState(() => _loading = true);
    await ApiService().fetchDataWithCache('/surveys', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null) {
        setState(() {
          _surveys = ApiService.ensureList(data);
          _loading = false;
        });
      }
    });
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an option before submitting.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService().post(
        '/surveys/${_answering!['id']}/respond',
        data: {
          'answers': {'vote': _selected},
        },
      );
      if (res.statusCode == 200) {
        final surveyTitle = _answering!['title']?.toString() ?? 'Ballot';
        final chosen = _selected;
        setState(() {
          _answering = null;
          _selected = '';
        });
        _fetch();
        if (mounted) {
          _showVoteSuccessDialog(title: surveyTitle, selected: chosen);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res.data?['message'] ?? 'Submission failed.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred while submitting your vote.')),
        );
      }
    }
    setState(() => _submitting = false);
  }

  void _showVoteSuccessDialog({required String title, required String selected}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0F0A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: _kGreen, size: 48),
            const SizedBox(height: 14),
            Text('Vote Cast Successfully!', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 6),
            Text(title, style: GoogleFonts.inter(fontSize: 14, color: AppColors.accentOrangeText), textAlign: TextAlign.center),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kOrange, foregroundColor: Colors.white, elevation: 0),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSurveyActive(dynamic s) {
    final activeVal = s['active'];
    final isActive = activeVal == true || activeVal == 1 || activeVal == 'true' || activeVal == null;
    if (!isActive) return false;
    final deadlineStr = s['deadline'] ?? s['expiry'];
    if (deadlineStr == null || deadlineStr.toString().isEmpty) return true;
    final d = DateTime.tryParse(deadlineStr.toString());
    if (d == null) return true;
    return DateTime(d.year, d.month, d.day, 23, 59, 59).isAfter(DateTime.now());
  }

  List<dynamic> get _active => _surveys.where(_isSurveyActive).toList();
  List<dynamic> get _past => _surveys.where((s) => !_isSurveyActive(s)).toList();

  List<dynamic> _filterList(List<dynamic> raw) {
    return raw.where((s) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final title = (s['title'] ?? '').toString().toLowerCase();
        final desc = (s['description'] ?? '').toString().toLowerCase();
        if (!title.contains(q) && !desc.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF140C08) : const Color(0xFFF8F4F0);
    final cardBg = isDark ? const Color(0xFF1E130D) : Colors.white;
    final border = isDark ? const Color(0xFF3D261C) : const Color(0xFFE8DED6);
    final textPrimary = isDark ? const Color(0xFFFFF8F3) : const Color(0xFF2B211D);
    final textMuted = isDark ? const Color(0xFFC8ADA0) : const Color(0xFF6F625B);

    final currentList = _tab == 'active' ? _active : _past;
    final filteredList = _filterList(currentList);

    return AppLayout(
      title: 'Surveys & Elections',
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_answering != null)
              _buildAnswerForm(isDark, cardBg, border, textPrimary, textMuted)
            else ...[
              // Simple Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Surveys & Elections', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary)),
                      const SizedBox(height: 2),
                      Text('Official trade ballots and industry consultations', style: GoogleFonts.inter(fontSize: 13, color: textMuted)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Simple Tabs
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border, width: 1.0),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _tab = 'active'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _tab == 'active' ? _kOrange.withAlpha(20) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Active (${_active.length})',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: _tab == 'active' ? _kOrange : textMuted,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _tab = 'past'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _tab == 'past' ? _kOrange.withAlpha(20) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Past (${_past.length})',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: _tab == 'past' ? _kOrange : textMuted,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Search bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border, width: 1.0),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: GoogleFonts.inter(fontSize: 14, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search consultations & ballots...',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: textMuted),
                    prefixIcon: Icon(Icons.search_rounded, size: 16, color: textMuted),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (_loading && filteredList.isEmpty)
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 3,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => const ShimmerListTile(),
                )
              else if (filteredList.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border, width: 1.0)),
                  child: Center(
                    child: Text('No surveys found.', style: GoogleFonts.inter(fontSize: 14, color: textMuted)),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredList.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) => _buildSurveyCard(filteredList[idx], cardBg, border, textPrimary, textMuted),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackBanner(String type, String title, bool isDark) {
    final isElection = type == 'election';
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? (isElection
                  ? [const Color(0xFF381A54), const Color(0xFF1E0E30)]
                  : [const Color(0xFF3A1F10), const Color(0xFF201008)])
              : (isElection
                  ? [const Color(0xFFEDE9FE), const Color(0xFFDDD6FE)]
                  : [const Color(0xFFFFEDD5), const Color(0xFFFED7AA)]),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -15,
            bottom: -15,
            child: Icon(
              isElection ? Icons.how_to_vote_rounded : Icons.poll_rounded,
              size: 100,
              color: (isElection ? _kPurple : _kOrange).withAlpha(35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Icon(
                      isElection ? Icons.how_to_vote_rounded : Icons.assessment_rounded,
                      size: 16,
                      color: isElection ? _kPurple : _kOrange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isElection ? 'OFFICIAL CUBAG BALLOT' : 'MEMBER TRADE SURVEY',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: isElection ? _kPurple : _kOrange,
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

  Widget _buildSurveyCard(dynamic s, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = s['title']?.toString() ?? 'Survey';
    final desc = s['description']?.toString() ?? '';
    final hasResponded = s['has_responded'] == true;
    final type = s['type']?.toString() ?? 'survey';
    final rawImage = s['cover_image'] ?? s['image_url'] ?? s['image'];
    final hasImage = rawImage != null && rawImage.toString().trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hasResponded ? _kGreen.withAlpha(100) : border, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Image or Styled Editorial Banner
          if (hasImage)
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CorsImageWidget(
                url: ApiService.resolveImageUrl(rawImage.toString()),
                fit: BoxFit.cover,
                placeholder: Container(
                  color: isDark ? const Color(0xFF281710) : const Color(0xFFF1EBE4),
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: _kOrange),
                  ),
                ),
                errorWidget: _buildFallbackBanner(type, title, isDark),
              ),
            )
          else
            _buildFallbackBanner(type, title, isDark),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (type == 'election' ? _kPurple : _kOrange).withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        type.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: type == 'election' ? _kPurple : _kOrange,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (hasResponded)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _kGreen.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                        child: Text('VOTED', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: _kGreen)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(desc, style: GoogleFonts.inter(fontSize: 13, color: textMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasResponded ? (isDark ? const Color(0xFF3D261C) : Colors.grey.shade300) : _kOrange,
                      foregroundColor: hasResponded ? (isDark ? Colors.white70 : Colors.black87) : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    onPressed: hasResponded ? null : () => setState(() {
                      _answering = s;
                      _selected = '';
                    }),
                    child: Text(hasResponded ? 'Voted' : 'Vote Now', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerForm(bool isDark, Color cardBg, Color border, Color textPrimary, Color textMuted) {
    final title = _answering!['title']?.toString() ?? 'Survey';
    final desc = _answering!['description']?.toString() ?? '';
    final rawImage = _answering!['cover_image'] ?? _answering!['image_url'] ?? _answering!['image'];
    final hasImage = rawImage != null && rawImage.toString().trim().isNotEmpty;

    List<dynamic> options = [];
    try {
      if (_answering!['options'] is List) {
        options = _answering!['options'];
      } else if (_answering!['options'] != null) {
        options = jsonDecode(_answering!['options'].toString());
      }
    } catch (_) {}

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
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _answering = null),
              ),
              Expanded(
                child: Text('Cast Your Vote', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 140,
                width: double.infinity,
                child: CorsImageWidget(
                  url: ApiService.resolveImageUrl(rawImage.toString()),
                  fit: BoxFit.cover,
                  errorWidget: _buildFallbackBanner(_answering!['type']?.toString() ?? 'survey', title, isDark),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.accentOrangeText)),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc, style: GoogleFonts.inter(fontSize: 13.5, color: textMuted)),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: border),
          const SizedBox(height: 16),

          ...options.map((opt) {
            final name = opt is Map ? (opt['name']?.toString() ?? '') : opt.toString();
            final isSelected = _selected == name;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => setState(() => _selected = name),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? _kOrange.withAlpha(20) : cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected ? _kOrange : border, width: isSelected ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: isSelected ? _kOrange : textMuted, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(name, style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.bold, color: textPrimary)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting...' : 'Submit Vote', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
