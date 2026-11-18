import 'dart:convert';
import 'package:flutter/services.dart';
import '../components/settlement_report.dart';
import '../components/admin_dialog.dart';
import '../components/filter_tabs.dart';
import '../components/admin_list.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/custom_dropdown.dart';
import '../components/skeleton_loader.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import '../utils/file_download.dart';
import '../design/cubag_design.dart';

const _kOrange = CubagColors.action;
const _kGreen = CubagColors.valid;
const _kRed = CubagColors.lapsed;
const _kAmber = CubagColors.due;
const _kBrown = Color(0xFF6B3E26);

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;

  // Date Range Filtering
  String _dateFilter = 'All Time';
  DateTime? _selectedSingleDate;
  DateTimeRange? _selectedDateRange;
  List<dynamic> _rawMembers = [];

  // Financial Stats
  double _revenue = 0.0;
  double _pendingRevenue = 0.0;
  double _failedRevenue = 0.0;
  double _renewalRevenue = 0.0;
  double _newMembershipRevenue = 0.0;
  double _courseRevenue = 0.0;
  double _otherRevenue = 0.0;
  String _financialStreamFilter = 'All Streams';
  List<dynamic> _transactions = [];
  final Map<String, double> _monthlyRevenue = {};

  // Membership Stats
  int _totalMembers = 0;
  Map<String, double> _statusCounts = {
    'active': 0,
    'pending': 0,
    'suspended': 0,
    'inactive': 0,
  };
  Map<String, double> _typeCounts = {
    'Licentiate': 0,
    'Associate': 0,
    'Corporate': 0,
  };

  // Operational Stats
  int _openTickets = 0;
  int _announcementsCount = 0;
  int _cargoSchedulesCount = 0;

  bool _isDateMatching(
    String? dateStr, {
    String? filterMode,
    DateTime? singleDate,
    DateTimeRange? customRange,
  }) {
    if (dateStr == null || dateStr.trim().isEmpty) return false;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return false;
    final date = parsed.toLocal();

    final mode = filterMode ?? _dateFilter;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (mode) {
      case 'Today':
        return !date.isBefore(todayStart) && !date.isAfter(todayEnd);

      case 'Yesterday':
        final yStart = todayStart.subtract(const Duration(days: 1));
        final yEnd = DateTime(yStart.year, yStart.month, yStart.day, 23, 59, 59, 999);
        return !date.isBefore(yStart) && !date.isAfter(yEnd);

      case 'Last 7 Days':
        final start7 = todayStart.subtract(const Duration(days: 6));
        return !date.isBefore(start7) && !date.isAfter(todayEnd);

      case 'Last 30 Days':
        final start30 = todayStart.subtract(const Duration(days: 29));
        return !date.isBefore(start30) && !date.isAfter(todayEnd);

      case 'This Month':
        final monthStart = DateTime(now.year, now.month, 1);
        final nextMonth = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);
        final monthEnd = nextMonth.subtract(const Duration(milliseconds: 1));
        return !date.isBefore(monthStart) && !date.isAfter(monthEnd);

      case 'Year to Date':
        final startOfYear = DateTime(now.year, 1, 1);
        return !date.isBefore(startOfYear) && !date.isAfter(todayEnd);

      case 'Single Date':
        final target = singleDate ?? _selectedSingleDate;
        if (target == null) return true;
        return date.year == target.year && date.month == target.month && date.day == target.day;

      case 'Custom Range':
      case 'Date Range':
        final range = customRange ?? _selectedDateRange;
        if (range == null) return true;
        final rStart = DateTime(range.start.year, range.start.month, range.start.day);
        final rEnd = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
        return !date.isBefore(rStart) && !date.isAfter(rEnd);

      case 'All Time':
      default:
        return true;
    }
  }

  bool _isWithinDateRange(String? dateStr) {
    return _isDateMatching(dateStr);
  }

  static String _formatDateShort(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _getDateFilterLabel({
    String? filterMode,
    DateTime? singleDate,
    DateTimeRange? customRange,
  }) {
    final mode = filterMode ?? _dateFilter;
    if (mode == 'Single Date') {
      final d = singleDate ?? _selectedSingleDate;
      if (d != null) return _formatDateShort(d);
      return 'Single Date';
    }
    if (mode == 'Custom Range' || mode == 'Date Range') {
      final r = customRange ?? _selectedDateRange;
      if (r != null) return '${_formatDateShort(r.start)} – ${_formatDateShort(r.end)}';
      return 'Date Range';
    }
    return mode;
  }

  String _getDateSuffix({
    String? filterMode,
    DateTime? singleDate,
    DateTimeRange? customRange,
  }) {
    final mode = filterMode ?? _dateFilter;
    if (mode == 'Single Date') {
      final d = singleDate ?? _selectedSingleDate;
      if (d != null) {
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
    }
    if (mode == 'Custom Range' || mode == 'Date Range') {
      final r = customRange ?? _selectedDateRange;
      if (r != null) {
        final s = '${r.start.year}-${r.start.month.toString().padLeft(2, '0')}-${r.start.day.toString().padLeft(2, '0')}';
        final e = '${r.end.year}-${r.end.month.toString().padLeft(2, '0')}-${r.end.day.toString().padLeft(2, '0')}';
        return '${s}_to_$e';
      }
    }
    return mode.replaceAll(' ', '_');
  }

  String _classifyTransactionCategory(Map<String, dynamic> tx) {
    final desc = (tx['description'] ?? '').toString().toLowerCase();
    final type = (tx['payment_type'] ?? tx['category'] ?? '').toString().toLowerCase();

    if (desc.contains('renewal') || desc.contains('licen') || type.contains('renewal')) {
      return 'Annual Renewal';
    } else if (desc.contains('registration') ||
               desc.contains('entrance') ||
               desc.contains('new member') ||
               desc.contains('onboarding') ||
               desc.contains('dossier') ||
               desc.contains('clearing & forwarding only') ||
               desc.contains('consolidation')) {
      return 'New Membership';
    } else if (desc.contains('course') ||
               desc.contains('cti') ||
               desc.contains('training') ||
               desc.contains('enroll') ||
               desc.contains('certification')) {
      return 'CTI Courses';
    } else {
      return 'Other Services';
    }
  }

  Map<String, double> get _filteredCategoryRevenue {
    if (_transactions.isEmpty && _dateFilter == 'All Time') {
      return {
        'Annual Renewal': _renewalRevenue,
        'New Membership': _newMembershipRevenue,
        'CTI Courses': _courseRevenue,
        'Other Services': _otherRevenue,
      };
    }
    final Map<String, double> catRev = {
      'Annual Renewal': 0.0,
      'New Membership': 0.0,
      'CTI Courses': 0.0,
      'Other Services': 0.0,
    };
    for (var tx in _transactions) {
      final statusStr = tx['status']?.toString().toLowerCase() ?? '';
      final isPaid = statusStr == 'paid' || statusStr == 'success' || statusStr == 'completed';
      if (isPaid && _isWithinDateRange(tx['date']?.toString() ?? tx['created_at']?.toString())) {
        final cat = _classifyTransactionCategory(tx is Map<String, dynamic> ? tx : Map<String, dynamic>.from(tx));
        final amt = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
        catRev[cat] = (catRev[cat] ?? 0.0) + amt;
      }
    }
    return catRev;
  }

  Map<String, int> get _filteredCategoryCounts {
    final Map<String, int> catCounts = {
      'Annual Renewal': 0,
      'New Membership': 0,
      'CTI Courses': 0,
      'Other Services': 0,
    };
    for (var tx in _transactions) {
      final statusStr = tx['status']?.toString().toLowerCase() ?? '';
      final isPaid = statusStr == 'paid' || statusStr == 'success' || statusStr == 'completed';
      if (isPaid && _isWithinDateRange(tx['date']?.toString() ?? tx['created_at']?.toString())) {
        final cat = _classifyTransactionCategory(tx is Map<String, dynamic> ? tx : Map<String, dynamic>.from(tx));
        catCounts[cat] = (catCounts[cat] ?? 0) + 1;
      }
    }
    return catCounts;
  }

  Map<String, Map<String, dynamic>> _computeBankRevenue({
    String? filterMode,
    DateTime? singleDate,
    DateTimeRange? customRange,
  }) {
    final Map<String, Map<String, dynamic>> banks = {
      '107113005326': {
        'name': 'GCB Bank',
        'account': '107113005326',
        'purpose': 'Operations, Registration, Vetting & Cloth',
        'codes': ['REG', 'ADM', 'GST', 'OTH'],
        'color': const Color(0xFFE89A3C),
        'icon': Icons.account_balance_rounded,
        'amount': 0.0,
        'count': 0,
      },
      '6010309212': {
        'name': 'Zenith Bank',
        'account': '6010309212',
        'purpose': 'Subscription Dues & Development Levy',
        'codes': ['SUB'],
        'color': const Color(0xFFD32F2F),
        'icon': Icons.account_balance_wallet_rounded,
        'amount': 0.0,
        'count': 0,
      },
      '1441002452360': {
        'name': 'Ecobank',
        'account': '1441002452360',
        'purpose': 'District Registration, Clearance & Welfare',
        'codes': ['DST'],
        'color': const Color(0xFF0288D1),
        'icon': Icons.domain_rounded,
        'amount': 0.0,
        'count': 0,
      },
      '1110045585101': {
        'name': 'NIB',
        'account': '1110045585101',
        'purpose': 'CTI Courses & CPD Professional Training',
        'codes': ['CTI', 'CPD'],
        'color': const Color(0xFF2E7D32),
        'icon': Icons.school_rounded,
        'amount': 0.0,
        'count': 0,
      },
    };

    for (var tx in _transactions) {
      final statusStr = tx['status']?.toString().toLowerCase() ?? '';
      final isPaid = statusStr == 'paid' || statusStr == 'success' || statusStr == 'completed';
      if (!isPaid || !_isDateMatching(tx['date']?.toString() ?? tx['created_at']?.toString(), filterMode: filterMode, singleDate: singleDate, customRange: customRange)) {
        continue;
      }

      final amt = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
      if (amt <= 0) continue;

      dynamic rawDist = tx['settlement_distribution'] ?? tx['payment_codes'];
      List<dynamic>? distList;
      if (rawDist is String && rawDist.trim().startsWith('[')) {
        try {
          distList = jsonDecode(rawDist) as List<dynamic>?;
        } catch (_) {}
      } else if (rawDist is List) {
        distList = rawDist;
      }

      if (distList != null && distList.isNotEmpty) {
        bool distributed = false;
        for (var item in distList) {
          if (item is Map) {
            final acc = (item['account_number'] ?? '').toString().replaceAll(RegExp(r'\s+'), '');
            final itemAmt = double.tryParse(item['amount']?.toString() ?? '0') ?? 0.0;
            final code = (item['code'] ?? item['payment_code'] ?? '').toString().toUpperCase();

            String? targetAcc;
            if (banks.containsKey(acc)) {
              targetAcc = acc;
            } else if (code == 'SUB') {
              targetAcc = '6010309212';
            } else if (code == 'DST') {
              targetAcc = '1441002452360';
            } else if (code == 'CTI' || code == 'CPD') {
              targetAcc = '1110045585101';
            } else if (code == 'REG' || code == 'ADM' || code == 'GST' || code == 'OTH') {
              targetAcc = '107113005326';
            }

            if (targetAcc != null && banks.containsKey(targetAcc) && itemAmt > 0) {
              banks[targetAcc]!['amount'] = (banks[targetAcc]!['amount'] as double) + itemAmt;
              banks[targetAcc]!['count'] = (banks[targetAcc]!['count'] as int) + 1;
              distributed = true;
            }
          }
        }
        if (distributed) continue;
      }

      // Fallback classification based on category
      final cat = _classifyTransactionCategory(tx is Map<String, dynamic> ? tx : Map<String, dynamic>.from(tx));
      if (cat == 'CTI Courses') {
        banks['1110045585101']!['amount'] = (banks['1110045585101']!['amount'] as double) + amt;
        banks['1110045585101']!['count'] = (banks['1110045585101']!['count'] as int) + 1;
      } else if (cat == 'Annual Renewal') {
        final subAmt = (amt >= 370) ? 120.0 : (amt * 0.15);
        final dstAmt = (amt >= 370) ? 250.0 : (amt * 0.25);
        final gcbAmt = (amt - subAmt - dstAmt).clamp(0.0, amt);

        banks['6010309212']!['amount'] = (banks['6010309212']!['amount'] as double) + subAmt;
        banks['6010309212']!['count'] = (banks['6010309212']!['count'] as int) + 1;

        banks['1441002452360']!['amount'] = (banks['1441002452360']!['amount'] as double) + dstAmt;
        banks['1441002452360']!['count'] = (banks['1441002452360']!['count'] as int) + 1;

        banks['107113005326']!['amount'] = (banks['107113005326']!['amount'] as double) + gcbAmt;
        banks['107113005326']!['count'] = (banks['107113005326']!['count'] as int) + 1;
      } else if (cat == 'New Membership') {
        final subAmt = (amt >= 370) ? 120.0 : (amt * 0.10);
        final dstAmt = (amt >= 370) ? 250.0 : (amt * 0.15);
        final gcbAmt = (amt - subAmt - dstAmt).clamp(0.0, amt);

        banks['6010309212']!['amount'] = (banks['6010309212']!['amount'] as double) + subAmt;
        banks['6010309212']!['count'] = (banks['6010309212']!['count'] as int) + 1;

        banks['1441002452360']!['amount'] = (banks['1441002452360']!['amount'] as double) + dstAmt;
        banks['1441002452360']!['count'] = (banks['1441002452360']!['count'] as int) + 1;

        banks['107113005326']!['amount'] = (banks['107113005326']!['amount'] as double) + gcbAmt;
        banks['107113005326']!['count'] = (banks['107113005326']!['count'] as int) + 1;
      } else {
        banks['107113005326']!['amount'] = (banks['107113005326']!['amount'] as double) + amt;
        banks['107113005326']!['count'] = (banks['107113005326']!['count'] as int) + 1;
      }
    }

    return banks;
  }

  Map<String, Map<String, dynamic>> get _filteredBankRevenue => _computeBankRevenue();

  // Getters for filtered Financial metrics
  double get _filteredRevenue {
    if (_transactions.isEmpty && _dateFilter == 'All Time') return _revenue;
    return _transactions
        .where(
          (tx) {
            final st = tx['status']?.toString().toLowerCase() ?? '';
            final isPaid = st == 'paid' || st == 'success' || st == 'completed';
            return isPaid && _isWithinDateRange(tx['date']?.toString() ?? tx['created_at']?.toString());
          },
        )
        .fold(
          0.0,
          (sum, tx) =>
              sum + (double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0),
        );
  }

  double get _filteredPendingRevenue {
    if (_transactions.isEmpty && _dateFilter == 'All Time') {
      return _pendingRevenue;
    }
    return _transactions
        .where(
          (tx) =>
              tx['status']?.toString().toLowerCase() == 'pending' &&
              _isWithinDateRange(
                tx['date']?.toString() ?? tx['created_at']?.toString(),
              ),
        )
        .fold(
          0.0,
          (sum, tx) =>
              sum + (double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0),
        );
  }

  double get _filteredFailedRevenue {
    if (_transactions.isEmpty && _dateFilter == 'All Time') {
      return _failedRevenue;
    }
    return _transactions
        .where(
          (tx) =>
              (tx['status']?.toString().toLowerCase() == 'failed' ||
                  tx['status']?.toString().toLowerCase() == 'overdue') &&
              _isWithinDateRange(
                tx['date']?.toString() ?? tx['created_at']?.toString(),
              ),
        )
        .fold(
          0.0,
          (sum, tx) =>
              sum + (double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0),
        );
  }

  List<dynamic> get _filteredTransactionsList {
    return _transactions
        .where((tx) {
          if (!_isWithinDateRange(tx['date']?.toString() ?? tx['created_at']?.toString())) {
            return false;
          }
          if (_financialStreamFilter != 'All Streams') {
            final cat = _classifyTransactionCategory(tx is Map<String, dynamic> ? tx : Map<String, dynamic>.from(tx));
            if (_financialStreamFilter == 'Renewal Dues' && cat != 'Annual Renewal') return false;
            if (_financialStreamFilter == 'New Membership' && cat != 'New Membership') return false;
            if (_financialStreamFilter == 'CTI Courses' && cat != 'CTI Courses') return false;
            if (_financialStreamFilter == 'Other' && cat != 'Other Services') return false;
          }
          return true;
        })
        .toList();
  }

  Map<String, double> get _filteredMonthlyRevenueMap {
    final Map<String, double> filteredMap = {};
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    for (var tx in _transactions) {
      if (tx['status']?.toString().toLowerCase() == 'paid' &&
          _isWithinDateRange(
            tx['date']?.toString() ?? tx['created_at']?.toString(),
          )) {
        try {
          final date = DateTime.parse(
            tx['date']?.toString() ?? tx['created_at']?.toString() ?? '',
          );
          final monthLabel =
              '${months[date.month - 1]} ${date.year.toString().substring(2)}';
          final amt = (double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0);
          filteredMap[monthLabel] = (filteredMap[monthLabel] ?? 0.0) + amt;
        } catch (e, st) {
          AppLogger.error('admin_analytics_page', e, st);
        }
      }
    }
    return filteredMap;
  }

  // Getters for filtered Membership metrics
  int get _filteredTotalMembersCount {
    if (_rawMembers.isEmpty) return _totalMembers;
    final filtered = _rawMembers.where((m) {
      final dateStr = m['created_at']?.toString() ?? m['date']?.toString();
      if (dateStr == null) return true;
      return _isWithinDateRange(dateStr);
    }).toList();
    return filtered.length;
  }

  Map<String, double> get _filteredStatusCountsMap {
    final Map<String, double> counts = {
      'active': 0,
      'pending': 0,
      'suspended': 0,
      'inactive': 0,
    };
    for (var m in _rawMembers) {
      final dateStr = m['created_at']?.toString() ?? m['date']?.toString();
      if (dateStr != null && !_isWithinDateRange(dateStr)) continue;

      final status = (m['status'] ?? '').toString().toLowerCase();
      if (counts.containsKey(status)) {
        counts[status] = counts[status]! + 1;
      }
    }
    return counts;
  }

  Map<String, double> get _filteredTypeCountsMap {
    final Map<String, double> counts = {
      'Licentiate': 0,
      'Associate': 0,
      'Corporate': 0,
    };
    for (var m in _rawMembers) {
      final dateStr = m['created_at']?.toString() ?? m['date']?.toString();
      if (dateStr != null && !_isWithinDateRange(dateStr)) continue;

      final type = (m['member_type'] ?? '').toString();
      if (type.isNotEmpty) {
        if (counts.containsKey(type)) {
          counts[type] = counts[type]! + 1;
        } else {
          counts[type] = (counts[type] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  Future<void> _exportCSV(String title, String csvContent) async {
    try {
      final fileName = '$title.csv';
      // Prepend UTF-8 BOM so Microsoft Excel immediately interprets Unicode and column separators correctly
      final bomCsv = '\uFEFF$csvContent';
      downloadFile(bomCsv, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Spreadsheet downloaded: $fileName',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e, st) {
      AppLogger.error('export_csv', e, st);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AdminDialog(
            title: 'Copy the export',
            subtitle: 'The file could not be downloaded here. Copy the text below and paste it into Excel.',
            actions: [
              TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: csvContent)),
                child: const Text('Copy'),
              ),
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            ],
            children: [
              Container(
                height: 220,
                padding: const EdgeInsets.all(CubagSpace.sm),
                decoration: BoxDecoration(color: CubagColors.sand, borderRadius: BorderRadius.circular(CubagRadius.control)),
                child: SingleChildScrollView(
                  child: SelectableText(csvContent, style: CubagType.caption.copyWith(fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _buildExportDatasetCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(CubagRadius.control),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: CubagSpace.sm, vertical: CubagSpace.sm),
        decoration: BoxDecoration(
          color: selected ? CubagColors.action.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(CubagRadius.control),
          border: Border.all(
            color: selected ? CubagColors.action : CubagColors.line,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? CubagColors.action : CubagColors.muted,
            ),
            const SizedBox(height: CubagSpace.xs),
            Text(
              title,
              style: CubagType.label.copyWith(
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? CubagColors.action : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: CubagType.caption.copyWith(
                fontSize: 10,
                color: CubagColors.muted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChoiceChip(
    String label,
    String current,
    ValueChanged<String> onSelected,
  ) {
    final isSelected = current == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : null,
      ),
      selectedColor: CubagColors.action,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  void _showExportDialog(bool isDark, Color cardBg, Color textPrimary, Color textMuted) {
    String selectedDataset = 'payments'; // 'payments', 'members', 'banks'
    String selectedFilterMode = _dateFilter == 'All Time' ? 'All Time' : _dateFilter;
    DateTime? dialogSingleDate = _selectedSingleDate ?? DateTime.now();
    DateTimeRange? dialogDateRange = _selectedDateRange ?? DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 7)),
      end: DateTime.now(),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          // Compute live preview counts
          int matchCount = 0;
          double matchRevenue = 0.0;
          if (selectedDataset == 'payments') {
            for (var tx in _transactions) {
              final d = tx['date']?.toString() ?? tx['created_at']?.toString();
              if (_isDateMatching(d, filterMode: selectedFilterMode, singleDate: dialogSingleDate, customRange: dialogDateRange)) {
                matchCount++;
                matchRevenue += (double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0);
              }
            }
          } else if (selectedDataset == 'members') {
            for (var m in _rawMembers) {
              final d = m['created_at']?.toString() ?? m['date']?.toString();
              if (d == null || _isDateMatching(d, filterMode: selectedFilterMode, singleDate: dialogSingleDate, customRange: dialogDateRange)) {
                matchCount++;
              }
            }
          } else if (selectedDataset == 'banks') {
            for (var tx in _transactions) {
              final st = tx['status']?.toString().toLowerCase() ?? '';
              final isPaid = st == 'paid' || st == 'success' || st == 'completed';
              final d = tx['date']?.toString() ?? tx['created_at']?.toString();
              if (isPaid && _isDateMatching(d, filterMode: selectedFilterMode, singleDate: dialogSingleDate, customRange: dialogDateRange)) {
                matchCount++;
                matchRevenue += (double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0);
              }
            }
          }

          final dateLabel = _getDateFilterLabel(
            filterMode: selectedFilterMode,
            singleDate: dialogSingleDate,
            customRange: dialogDateRange,
          );

          return AdminDialog(
            title: 'Export analytics & reports',
            subtitle: 'Export payments, members, or bank settlements with custom date filtering.',
            maxWidth: 580,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download CSV'),
                onPressed: () {
                  Navigator.pop(ctx);
                  if (selectedDataset == 'payments') {
                    _exportFinancialsCSV(
                      filterMode: selectedFilterMode,
                      singleDate: dialogSingleDate,
                      customRange: dialogDateRange,
                    );
                  } else if (selectedDataset == 'members') {
                    _exportMembersCSV(
                      filterMode: selectedFilterMode,
                      singleDate: dialogSingleDate,
                      customRange: dialogDateRange,
                    );
                  } else {
                    _exportBankSettlementsCSV(
                      filterMode: selectedFilterMode,
                      singleDate: dialogSingleDate,
                      customRange: dialogDateRange,
                    );
                  }
                },
              ),
            ],
            children: [
              // 1. Dataset Selection
              Text('1. SELECT DATASET', style: CubagType.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5, color: textMuted)),
              const SizedBox(height: CubagSpace.xs),
              Row(
                children: [
                  Expanded(
                    child: _buildExportDatasetCard(
                      title: 'Payments',
                      subtitle: 'Ledger & refs',
                      icon: Icons.payments_outlined,
                      selected: selectedDataset == 'payments',
                      onTap: () => setModalState(() => selectedDataset = 'payments'),
                    ),
                  ),
                  const SizedBox(width: CubagSpace.xs),
                  Expanded(
                    child: _buildExportDatasetCard(
                      title: 'Members',
                      subtitle: 'Roster & standing',
                      icon: Icons.people_outline_rounded,
                      selected: selectedDataset == 'members',
                      onTap: () => setModalState(() => selectedDataset = 'members'),
                    ),
                  ),
                  const SizedBox(width: CubagSpace.xs),
                  Expanded(
                    child: _buildExportDatasetCard(
                      title: 'Bank Accounts',
                      subtitle: 'Settlements',
                      icon: Icons.account_balance_outlined,
                      selected: selectedDataset == 'banks',
                      onTap: () => setModalState(() => selectedDataset = 'banks'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CubagSpace.md),

              // 2. Date Filter Selection
              Text('2. DATE SCOPE', style: CubagType.caption.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5, color: textMuted)),
              const SizedBox(height: CubagSpace.xs),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildFilterChoiceChip('All Time', selectedFilterMode, (v) => setModalState(() => selectedFilterMode = v)),
                  _buildFilterChoiceChip('Today', selectedFilterMode, (v) => setModalState(() => selectedFilterMode = v)),
                  _buildFilterChoiceChip('Yesterday', selectedFilterMode, (v) => setModalState(() => selectedFilterMode = v)),
                  _buildFilterChoiceChip('Last 7 Days', selectedFilterMode, (v) => setModalState(() => selectedFilterMode = v)),
                  _buildFilterChoiceChip('Last 30 Days', selectedFilterMode, (v) => setModalState(() => selectedFilterMode = v)),
                  _buildFilterChoiceChip('This Month', selectedFilterMode, (v) => setModalState(() => selectedFilterMode = v)),
                  _buildFilterChoiceChip('Single Date', selectedFilterMode, (v) async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dialogSingleDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setModalState(() {
                        dialogSingleDate = picked;
                        selectedFilterMode = 'Single Date';
                      });
                    }
                  }),
                  _buildFilterChoiceChip('Date Range', selectedFilterMode, (v) async {
                    final picked = await showDateRangePicker(
                      context: context,
                      initialDateRange: dialogDateRange ?? DateTimeRange(
                        start: DateTime.now().subtract(const Duration(days: 7)),
                        end: DateTime.now(),
                      ),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setModalState(() {
                        dialogDateRange = picked;
                        selectedFilterMode = 'Date Range';
                      });
                    }
                  }),
                ],
              ),
              const SizedBox(height: CubagSpace.sm),

              // If Single Date or Date Range is active, show the picker change tile
              if (selectedFilterMode == 'Single Date')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: CubagSpace.sm, vertical: CubagSpace.xs),
                  decoration: BoxDecoration(
                    color: CubagColors.action.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(CubagRadius.control),
                    border: Border.all(color: CubagColors.action.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_rounded, size: 18, color: CubagColors.action),
                      const SizedBox(width: CubagSpace.xs),
                      Expanded(
                        child: Text(
                          'Selected date: ${dialogSingleDate != null ? _formatDateShort(dialogSingleDate!) : "None"}',
                          style: CubagType.caption.copyWith(fontWeight: FontWeight.w600, color: CubagColors.action),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                        label: const Text('Change'),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dialogSingleDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setModalState(() => dialogSingleDate = picked);
                          }
                        },
                      ),
                    ],
                  ),
                ),

              if (selectedFilterMode == 'Date Range')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: CubagSpace.sm, vertical: CubagSpace.xs),
                  decoration: BoxDecoration(
                    color: CubagColors.action.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(CubagRadius.control),
                    border: Border.all(color: CubagColors.action.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range_rounded, size: 18, color: CubagColors.action),
                      const SizedBox(width: CubagSpace.xs),
                      Expanded(
                        child: Text(
                          'Range: ${dialogDateRange != null ? "${_formatDateShort(dialogDateRange!.start)} – ${_formatDateShort(dialogDateRange!.end)}" : "None"}',
                          style: CubagType.caption.copyWith(fontWeight: FontWeight.w600, color: CubagColors.action),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                        label: const Text('Change'),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            initialDateRange: dialogDateRange ?? DateTimeRange(
                              start: DateTime.now().subtract(const Duration(days: 7)),
                              end: DateTime.now(),
                            ),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setModalState(() => dialogDateRange = picked);
                          }
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: CubagSpace.md),

              // 3. Live Matching Preview Box
              Container(
                padding: const EdgeInsets.all(CubagSpace.sm),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF261D18) : CubagColors.sand,
                  borderRadius: BorderRadius.circular(CubagRadius.control),
                  border: Border.all(color: CubagColors.line),
                ),
                child: Row(
                  children: [
                    Icon(
                      matchCount > 0 ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                      size: 20,
                      color: matchCount > 0 ? CubagColors.valid : CubagColors.due,
                    ),
                    const SizedBox(width: CubagSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            matchCount > 0
                                ? (selectedDataset == 'members'
                                    ? '$matchCount matching members'
                                    : '$matchCount records found (${_cedis(matchRevenue)})')
                                : 'No records match this date filter',
                            style: CubagType.label.copyWith(
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Active Scope: $dateLabel',
                            style: CubagType.caption.copyWith(color: textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _exportFinancialsCSV({
    String? filterMode,
    DateTime? singleDate,
    DateTimeRange? customRange,
  }) {
    final filteredTx = _transactions
        .where(
          (tx) => _isDateMatching(
            tx['date']?.toString() ?? tx['created_at']?.toString(),
            filterMode: filterMode,
            singleDate: singleDate,
            customRange: customRange,
          ),
        )
        .toList();
    final buffer = StringBuffer();
    buffer.writeln('Transaction ID,Date & Time,Member Name,Company,Member Category,Amount (GHS),Payment Method,Transaction Reference,Status,Description');
    
    for (var tx in filteredTx) {
      final id = tx['id']?.toString() ?? '';
      final date = tx['date']?.toString() ?? tx['created_at']?.toString() ?? '';
      final name = '"${(tx['member_name']?.toString() ?? '').replaceAll('"', '""')}"';
      final company = '"${(tx['company']?.toString() ?? '').replaceAll('"', '""')}"';
      final type = '"${(tx['member_type']?.toString() ?? 'Licentiate').replaceAll('"', '""')}"';
      final amount = tx['amount']?.toString() ?? '0.00';
      final method = '"${(tx['payment_method']?.toString() ?? tx['channel']?.toString() ?? 'Mobile Money').replaceAll('"', '""')}"';
      final ref = '"${(tx['reference']?.toString() ?? tx['payment_ref']?.toString() ?? '').replaceAll('"', '""')}"';
      final status = '"${(tx['status']?.toString() ?? 'completed').replaceAll('"', '""')}"';
      final desc = '"${(tx['description']?.toString() ?? 'Annual Dues / Service Fee').replaceAll('"', '""')}"';
      buffer.writeln('$id,$date,$name,$company,$type,$amount,$method,$ref,$status,$desc');
    }
    final suffix = _getDateSuffix(filterMode: filterMode, singleDate: singleDate, customRange: customRange);
    _exportCSV('CUBAG_Financial_Ledger_$suffix', buffer.toString());
  }

  void _exportMembersCSV({
    String? filterMode,
    DateTime? singleDate,
    DateTimeRange? customRange,
  }) {
    final filteredMembers = _rawMembers.where((m) {
      final dateStr = m['created_at']?.toString() ?? m['date']?.toString();
      if (dateStr == null) return true;
      return _isDateMatching(
        dateStr,
        filterMode: filterMode,
        singleDate: singleDate,
        customRange: customRange,
      );
    }).toList();
    final buffer = StringBuffer();
    buffer.writeln('Member ID,Full Name,Company,Email,Phone,Member Category,District(s),License Number,TIN,Status,Compliance Score,Star Rating,Registration Date');
    
    for (var m in filteredMembers) {
      final id = m['id']?.toString() ?? '';
      final name = '"${(m['name']?.toString() ?? '').replaceAll('"', '""')}"';
      final company = '"${(m['company']?.toString() ?? '').replaceAll('"', '""')}"';
      final email = '"${(m['email']?.toString() ?? '').replaceAll('"', '""')}"';
      final phone = '"${(m['phone']?.toString() ?? '').replaceAll('"', '""')}"';
      final type = '"${(m['member_type']?.toString() ?? 'Licentiate').replaceAll('"', '""')}"';
      final port = '"${(m['port_of_operation']?.toString() ?? m['location']?.toString() ?? 'Tema Port').replaceAll('"', '""')}"';
      final lic = '"${(m['license_number']?.toString() ?? '').replaceAll('"', '""')}"';
      final tin = '"${(m['tin']?.toString() ?? '').replaceAll('"', '""')}"';
      final status = '"${(m['status']?.toString() ?? 'active').replaceAll('"', '""')}"';
      final score = m['compliance_score']?.toString() ?? '100';
      final rating = m['star_rating']?.toString() ?? '5.0';
      final date = m['created_at']?.toString() ?? m['date']?.toString() ?? '';
      buffer.writeln('$id,$name,$company,$email,$phone,$type,$port,$lic,$tin,$status,$score,$rating,$date');
    }
    final suffix = _getDateSuffix(filterMode: filterMode, singleDate: singleDate, customRange: customRange);
    _exportCSV('CUBAG_Members_Roster_$suffix', buffer.toString());
  }

  void _exportBankSettlementsCSV({
    String? filterMode,
    DateTime? singleDate,
    DateTimeRange? customRange,
  }) {
    final banks = _computeBankRevenue(
      filterMode: filterMode,
      singleDate: singleDate,
      customRange: customRange,
    );

    final buffer = StringBuffer();
    buffer.writeln('Bank Settlement Summary');
    buffer.writeln('Bank Name,Account Number,Allocated Purpose,Total Allocated (GHS),Transaction Count');
    for (var entry in banks.entries) {
      final b = entry.value;
      final name = '"${b['name']}"';
      final acc = '"${b['account']}"';
      final purpose = '"${b['purpose']}"';
      final amt = (b['amount'] as double? ?? 0.0).toStringAsFixed(2);
      final count = b['count'] ?? 0;
      buffer.writeln('$name,$acc,$purpose,$amt,$count');
    }
    buffer.writeln('');
    buffer.writeln('Transaction Breakdown');
    buffer.writeln('Transaction ID,Date,Member Name,Reference,Total Amount (GHS),Payment Channel,Allocated Bank,Description');

    for (var tx in _transactions) {
      final statusStr = tx['status']?.toString().toLowerCase() ?? '';
      final isPaid = statusStr == 'paid' || statusStr == 'success' || statusStr == 'completed';
      if (!isPaid || !_isDateMatching(tx['date']?.toString() ?? tx['created_at']?.toString(), filterMode: filterMode, singleDate: singleDate, customRange: customRange)) {
        continue;
      }
      final id = tx['id']?.toString() ?? '';
      final date = tx['date']?.toString() ?? tx['created_at']?.toString() ?? '';
      final name = '"${(tx['member_name']?.toString() ?? '').replaceAll('"', '""')}"';
      final ref = '"${(tx['reference']?.toString() ?? tx['payment_ref']?.toString() ?? '').replaceAll('"', '""')}"';
      final amt = tx['amount']?.toString() ?? '0.00';
      final method = '"${(tx['payment_method']?.toString() ?? tx['channel']?.toString() ?? 'Mobile Money').replaceAll('"', '""')}"';
      final cat = _classifyTransactionCategory(tx is Map<String, dynamic> ? tx : Map<String, dynamic>.from(tx));
      String allocatedBank = 'GCB Bank (107113005326)';
      if (cat == 'CTI Courses') {
        allocatedBank = 'NIB Bank (1110045585101)';
      } else if (cat == 'Annual Renewal' || cat == 'New Membership') {
        allocatedBank = 'Multi-Split (GCB / Ecobank / Zenith)';
      }
      final desc = '"${(tx['description']?.toString() ?? '').replaceAll('"', '""')}"';
      buffer.writeln('$id,$date,$name,$ref,$amt,$method,"$allocatedBank",$desc');
    }

    final suffix = _getDateSuffix(filterMode: filterMode, singleDate: singleDate, customRange: customRange);
    _exportCSV('CUBAG_Bank_Settlements_$suffix', buffer.toString());
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    bool financialFailed = false;
    bool membersFailed = false;

    // 1. Dashboard Stats
    try {
      final dashboardRes = await ApiService().get('/admin/dashboard');
      if (dashboardRes.statusCode == 200 && dashboardRes.data is Map) {
        final dData = dashboardRes.data as Map<String, dynamic>;
        final kpis = dData['kpis'] as Map<String, dynamic>? ?? {};
        _totalMembers =
            (kpis['total_members'] ?? kpis['members_count'] ?? 0) as int;
        _openTickets =
            (kpis['open_tickets'] ?? kpis['tickets_count'] ?? 0) as int;
      }
    } catch (e, st) {
      AppLogger.error('admin_analytics_page dashboard', e, st);
    }

    // 2. Financial Stats
    try {
      final financialRes = await ApiService().get(
        '/payments/admin/all?limit=500',
      );
      if (financialRes.statusCode == 200 && financialRes.data is Map) {
        final fData = financialRes.data as Map<String, dynamic>;
        final kpis = fData['kpis'] as Map<String, dynamic>? ?? {};
        _revenue = (double.tryParse(kpis['revenue']?.toString() ?? '0') ?? 0.0);
        _pendingRevenue =
            (double.tryParse(kpis['pending']?.toString() ?? '0') ?? 0.0);
        _failedRevenue =
            (double.tryParse(kpis['failed']?.toString() ?? '0') ?? 0.0);

        final bk = kpis['breakdown'] as Map<String, dynamic>? ?? {};
        _renewalRevenue = (double.tryParse(bk['renewal']?.toString() ?? '0') ?? 0.0);
        _newMembershipRevenue = (double.tryParse(bk['new_membership']?.toString() ?? '0') ?? 0.0);
        _courseRevenue = (double.tryParse(bk['course']?.toString() ?? '0') ?? 0.0);
        _otherRevenue = (double.tryParse(bk['other']?.toString() ?? '0') ?? 0.0);

        final rawTx =
            fData['data'] ?? fData['transactions'] ?? fData['payments'] ?? [];
        _transactions = rawTx is List ? rawTx : [];

        _monthlyRevenue.clear();
        final months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        for (var tx in _transactions) {
          final statusStr = tx['status']?.toString().toLowerCase() ?? '';
          final dateStr =
              tx['date']?.toString() ?? tx['created_at']?.toString();
          if (statusStr == 'paid' && dateStr != null) {
            try {
              final date = DateTime.parse(dateStr);
              final monthLabel =
                  '${months[date.month - 1]} ${date.year.toString().substring(2)}';
              final amt =
                  (double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0);
              _monthlyRevenue[monthLabel] =
                  (_monthlyRevenue[monthLabel] ?? 0.0) + amt;
            } catch (e, st) {
              AppLogger.error('admin_analytics_page monthly parsing', e, st);
            }
          }
        }
      } else {
        financialFailed = true;
      }
    } catch (e, st) {
      financialFailed = true;
      AppLogger.error('admin_analytics_page financials', e, st);
    }

    // 3. Members Stats
    try {
      final membersRes = await ApiService().get('/members/admin/all?limit=500');
      if (membersRes.statusCode == 200) {
        List<dynamic> members = [];
        if (membersRes.data is List) {
          members = membersRes.data;
        } else if (membersRes.data is Map) {
          final mData = membersRes.data as Map<String, dynamic>;
          members = (mData['data'] ?? mData['members'] ?? []) as List<dynamic>;
        }
        _rawMembers = members;
        if (members.length > _totalMembers) {
          _totalMembers = members.length;
        }

        // Reset counts
        _statusCounts = {
          'active': 0,
          'pending': 0,
          'suspended': 0,
          'inactive': 0,
        };
        _typeCounts = {'Licentiate': 0, 'Associate': 0, 'Corporate': 0};

        for (var m in members) {
          final status = (m['status'] ?? '').toString().toLowerCase();
          if (_statusCounts.containsKey(status)) {
            _statusCounts[status] = _statusCounts[status]! + 1;
          }

          final type = (m['member_type'] ?? '').toString();
          if (type.isNotEmpty) {
            if (_typeCounts.containsKey(type)) {
              _typeCounts[type] = _typeCounts[type]! + 1;
            } else {
              _typeCounts[type] = (_typeCounts[type] ?? 0) + 1;
            }
          }
        }
      } else {
        membersFailed = true;
      }
    } catch (e, st) {
      membersFailed = true;
      AppLogger.error('admin_analytics_page members', e, st);
    }

    // 4. Cargo Schedules
    try {
      final cargoRes = await ApiService().get('/schedules');
      if (cargoRes.statusCode == 200) {
        if (cargoRes.data is List) {
          _cargoSchedulesCount = (cargoRes.data as List).length;
        } else if (cargoRes.data is Map) {
          final cData = cargoRes.data as Map<String, dynamic>;
          final cList =
              (cData['schedules'] ?? cData['data'] ?? []) as List<dynamic>;
          _cargoSchedulesCount = cList.length;
        }
      }
    } catch (_) {}

    // 5. Announcements
    try {
      final announcementsRes = await ApiService().get('/announcements');
      if (announcementsRes.statusCode == 200) {
        if (announcementsRes.data is List) {
          _announcementsCount = (announcementsRes.data as List).length;
        } else if (announcementsRes.data is Map) {
          final aData = announcementsRes.data as Map<String, dynamic>;
          final aList =
              (aData['announcements'] ?? aData['data'] ?? []) as List<dynamic>;
          _announcementsCount = aList.length;
        }
      }
    } catch (_) {}

    if (financialFailed || membersFailed) {
      _error =
          'Failed to fetch some analytics data. Visualizing available records.';
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  /// "GH₵ 12,816": whole cedis with thousands separators.
  static String _cedis(num v) {
    final t = v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return 'GH₵ $t';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF22140E) : CubagColors.paper;
    final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final textPrimary = isDark ? Colors.white : CubagColors.ink;
    final textMuted = isDark ? const Color(0xFFB0A298) : CubagColors.muted;
    final innerBg = isDark ? CubagColors.ink : CubagColors.sand;
    final tab = _tabController.index;

    return AppLayout(
      title: 'Revenue',
      hideSearch: false,
      scrollable: true,
      child: _loading
          ? const DashboardSkeleton()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdminHeader(
                      title: 'Revenue and activity',
                      subtitle: 'Money received, members and service activity for the period you choose.',
                      actions: [
                        CustomDropdown<String>(
                          value: _dateFilter,
                          width: 175,
                          dense: true,
                          items: [
                            const DropdownItem(value: 'All Time', label: 'All time'),
                            const DropdownItem(value: 'Today', label: 'Today'),
                            const DropdownItem(value: 'Yesterday', label: 'Yesterday'),
                            const DropdownItem(value: 'Last 7 Days', label: 'Last 7 days'),
                            const DropdownItem(value: 'Last 30 Days', label: 'Last 30 days'),
                            const DropdownItem(value: 'This Month', label: 'This month'),
                            const DropdownItem(value: 'Year to Date', label: 'This year'),
                            DropdownItem(
                              value: 'Single Date',
                              label: _selectedSingleDate != null && _dateFilter == 'Single Date'
                                  ? 'Single: ${_selectedSingleDate!.day}/${_selectedSingleDate!.month}'
                                  : 'Single date...',
                            ),
                            DropdownItem(
                              value: 'Custom Range',
                              label: _selectedDateRange != null && _dateFilter == 'Custom Range'
                                  ? 'Range: ${_selectedDateRange!.start.day}/${_selectedDateRange!.start.month}–${_selectedDateRange!.end.day}/${_selectedDateRange!.end.month}'
                                  : 'Date range...',
                            ),
                          ],
                          onChanged: (v) async {
                            if (v == 'Single Date') {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedSingleDate ?? now,
                                firstDate: DateTime(2020),
                                lastDate: now,
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedSingleDate = picked;
                                  _dateFilter = 'Single Date';
                                });
                              }
                            } else if (v == 'Custom Range') {
                              final now = DateTime.now();
                              final picked = await showDateRangePicker(
                                context: context,
                                initialDateRange: _selectedDateRange ?? DateTimeRange(
                                  start: now.subtract(const Duration(days: 7)),
                                  end: now,
                                ),
                                firstDate: DateTime(2020),
                                lastDate: now,
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedDateRange = picked;
                                  _dateFilter = 'Custom Range';
                                });
                              }
                            } else {
                              setState(() => _dateFilter = v);
                            }
                          },
                        ),
                        if (_dateFilter == 'Single Date' || _dateFilter == 'Custom Range')
                          IconButton(
                            tooltip: 'Reset date filter to All Time',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() => _dateFilter = 'All Time'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _showExportDialog(isDark, cardBg, textPrimary, textMuted),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Export'),
                        ),
                      ],
                    ),
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: CubagSpace.md),
                        padding: const EdgeInsets.all(CubagSpace.md),
                        decoration: BoxDecoration(
                          color: CubagColors.lapsedTint,
                          borderRadius: BorderRadius.circular(CubagRadius.card),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: CubagColors.lapsed, size: 20),
                            const SizedBox(width: CubagSpace.sm),
                            Expanded(child: Text(_error!, style: CubagType.label.copyWith(color: CubagColors.lapsed))),
                            TextButton(onPressed: _fetchData, child: const Text('Try again')),
                          ],
                        ),
                      ),
                    AdminFigureStrip(figures: [
                      AdminFigure('Money received', _cedis(_filteredRevenue), color: CubagColors.valid),
                      AdminFigure('Members', '$_filteredTotalMembersCount'),
                      AdminFigure('Cargo schedules', '$_cargoSchedulesCount'),
                      AdminFigure('Open tickets', '$_openTickets', color: _openTickets > 0 ? CubagColors.due : null),
                    ]),
                    const SizedBox(height: CubagSpace.lg),
                    FilterTabs(
                      tabs: const [('0', 'Money'), ('1', 'Members'), ('2', 'Operations'), ('3', 'Settlement')],
                      selected: '$tab',
                      onSelected: (k) => setState(() => _tabController.index = int.parse(k)),
                    ),
                    const SizedBox(height: CubagSpace.md),
                    if (tab == 0) _buildFinancialTab(isDark, cardBg, border, textPrimary, textMuted, innerBg),
                    if (tab == 1) _buildMembershipTab(isDark, cardBg, border, textPrimary, textMuted, innerBg),
                    if (tab == 2) _buildOperationsTab(isDark, cardBg, border, textPrimary, textMuted, innerBg),
                    if (tab == 3) SettlementReport(onExport: _exportCSV),
                    const SizedBox(height: CubagSpace.xl),
                  ],
                ),
              ),
            ),
    );
  }

  String _formatCurrency(double amt) {
    return amt.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  Widget _buildFinancialTab(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
    Color innerBg,
  ) {
    // Generate monthly revenue list
    final filteredMonthly = _filteredMonthlyRevenueMap;
    // Keys look like 'Aug 26'; order them by date, not alphabetically.
    const monthOrder = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    int monthKey(String k) {
      final parts = k.split(' ');
      final m = monthOrder.indexOf(parts.first);
      final y = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return y * 12 + (m < 0 ? 0 : m);
    }
    final sortedMonths = filteredMonthly.keys.toList()..sort((a, b) => monthKey(a).compareTo(monthKey(b)));
    final values = sortedMonths.map((m) => filteredMonthly[m] ?? 0.0).toList();

    final maxVal = values.isNotEmpty
        ? values.reduce((curr, next) => curr > next ? curr : next)
        : 1000.0;
    final filteredTx = _filteredTransactionsList;

    // Stream breakdowns
    final catRev = _filteredCategoryRevenue;
    final catCounts = _filteredCategoryCounts;
    final totalRev = _filteredRevenue > 0 ? _filteredRevenue : 1.0;

    final renewalAmt = catRev['Annual Renewal'] ?? 0.0;
    final newMemAmt = catRev['New Membership'] ?? 0.0;
    final courseAmt = catRev['CTI Courses'] ?? 0.0;
    final otherAmt = catRev['Other Services'] ?? 0.0;

    final renewalPct = (renewalAmt / totalRev * 100).clamp(0, 100).toStringAsFixed(1);
    final newMemPct = (newMemAmt / totalRev * 100).clamp(0, 100).toStringAsFixed(1);
    final coursePct = (courseAmt / totalRev * 100).clamp(0, 100).toStringAsFixed(1);
    final otherPct = (otherAmt / totalRev * 100).clamp(0, 100).toStringAsFixed(1);

    return SingleChildScrollView(
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── REVENUE STREAM BREAKDOWN SECTION ─────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 20 : 4),
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _kOrange.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: _kOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Revenue by type',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            'Confirmed payments for renewals, new membership dues and courses.',
                            style: TextStyle(
                              fontSize: 16,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _kGreen.withAlpha(15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kGreen.withAlpha(40)),
                      ),
                      child: Text(
                        'Total: GH₵ ${_formatCurrency(_filteredRevenue)}',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: _kGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4 Category KPI Cards Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    return isWide
                        ? Row(
                            children: [
                              Expanded(
                                child: _buildStreamCard(
                                  title: 'Renewal dues',
                                  subtitle: 'Member compliance & renewals',
                                  amount: renewalAmt,
                                  percentage: renewalPct,
                                  count: catCounts['Annual Renewal'] ?? 0,
                                  icon: Icons.autorenew_rounded,
                                  color: _kGreen,
                                  countSuffix: 'renewals',
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textMuted: textMuted,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildStreamCard(
                                  title: 'New members',
                                  subtitle: 'Applications & entrance dues',
                                  amount: newMemAmt,
                                  percentage: newMemPct,
                                  count: catCounts['New Membership'] ?? 0,
                                  icon: Icons.person_add_alt_1_rounded,
                                  color: _kOrange,
                                  countSuffix: 'onboarding',
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textMuted: textMuted,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildStreamCard(
                                  title: 'Courses',
                                  subtitle: 'Accredited academy courses',
                                  amount: courseAmt,
                                  percentage: coursePct,
                                  count: catCounts['CTI Courses'] ?? 0,
                                  icon: Icons.school_rounded,
                                  color: _kAmber,
                                  countSuffix: 'enrolled',
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textMuted: textMuted,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildStreamCard(
                                  title: 'Other fees',
                                  subtitle: 'ID cards, badges and other items',
                                  amount: otherAmt,
                                  percentage: otherPct,
                                  count: catCounts['Other Services'] ?? 0,
                                  icon: Icons.miscellaneous_services_rounded,
                                  color: _kBrown,
                                  countSuffix: 'payments',
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textMuted: textMuted,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _buildStreamCard(
                                title: 'Renewal dues',
                                subtitle: 'Member compliance & renewals',
                                amount: renewalAmt,
                                percentage: renewalPct,
                                count: catCounts['Annual Renewal'] ?? 0,
                                icon: Icons.autorenew_rounded,
                                color: _kGreen,
                                countSuffix: 'renewals',
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                              ),
                              const SizedBox(height: 10),
                              _buildStreamCard(
                                title: 'New members',
                                subtitle: 'Applications & entrance dues',
                                amount: newMemAmt,
                                percentage: newMemPct,
                                count: catCounts['New Membership'] ?? 0,
                                icon: Icons.person_add_alt_1_rounded,
                                color: _kOrange,
                                countSuffix: 'onboarding',
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                              ),
                              const SizedBox(height: 10),
                              _buildStreamCard(
                                title: 'Courses',
                                subtitle: 'Accredited academy courses',
                                amount: courseAmt,
                                percentage: coursePct,
                                count: catCounts['CTI Courses'] ?? 0,
                                icon: Icons.school_rounded,
                                color: _kAmber,
                                countSuffix: 'enrolled',
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                              ),
                              const SizedBox(height: 10),
                              _buildStreamCard(
                                title: 'Other fees',
                                subtitle: 'ID cards, badges and other items',
                                amount: otherAmt,
                                percentage: otherPct,
                                count: catCounts['Other Services'] ?? 0,
                                icon: Icons.miscellaneous_services_rounded,
                                color: _kBrown,
                                countSuffix: 'payments',
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                              ),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 16),

                // Multi-Segmented Proportional Distribution Bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Share of revenue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textMuted,
                          ),
                        ),
                        Text(
                          'Of confirmed payments',
                          style: TextStyle(
                            fontSize: 15,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 12,
                        child: Row(
                          children: [
                            if (renewalAmt > 0)
                              Expanded(
                                flex: (renewalAmt * 100).toInt(),
                                child: Container(color: _kGreen),
                              ),
                            if (newMemAmt > 0)
                              Expanded(
                                flex: (newMemAmt * 100).toInt(),
                                child: Container(color: _kOrange),
                              ),
                            if (courseAmt > 0)
                              Expanded(
                                flex: (courseAmt * 100).toInt(),
                                child: Container(color: _kAmber),
                              ),
                            if (otherAmt > 0)
                              Expanded(
                                flex: (otherAmt * 100).toInt(),
                                child: Container(color: _kBrown),
                              ),
                            if (totalRev <= 1.0 && renewalAmt == 0 && newMemAmt == 0 && courseAmt == 0 && otherAmt == 0)
                              Expanded(
                                child: Container(color: isDark ? const Color(0xFF3D261C) : CubagColors.line),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _buildLegendItem('Renewal dues ($renewalPct%)', _kGreen, textMuted),
                        _buildLegendItem('New members ($newMemPct%)', _kOrange, textMuted),
                        _buildLegendItem('Courses ($coursePct%)', _kAmber, textMuted),
                        _buildLegendItem('Other fees ($otherPct%)', _kBrown, textMuted),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── BANK ACCOUNT SETTLEMENT DISTRIBUTION SECTION ─────────────────
          _buildBankSettlementSection(isDark, cardBg, border, textPrimary, textMuted, innerBg),
          const SizedBox(height: 14),

          // ── TREND CHART & STATUS DISTRIBUTION ─────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Revenue by month (GH₵)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      sortedMonths.isEmpty
                          ? SizedBox(
                              height: 190,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.bar_chart,
                                      size: 40,
                                      color: textMuted,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No revenue data available',
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _CustomBarChart(
                              values: values,
                              labels: sortedMonths,
                              maxValue: maxVal,
                              color: _kOrange,
                              isDark: isDark,
                              textMuted: textMuted,
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paid and outstanding',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _financialMetricBar(
                        'Received',
                        _filteredRevenue,
                        _kGreen,
                        isDark,
                        textPrimary,
                        textMuted,
                      ),
                      _financialMetricBar(
                        'Waiting to be paid',
                        _filteredPendingRevenue,
                        _kAmber,
                        isDark,
                        textPrimary,
                        textMuted,
                      ),
                      _financialMetricBar(
                        'Failed or overdue',
                        _filteredFailedRevenue,
                        _kRed,
                        isDark,
                        textPrimary,
                        textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── RECENT TRANSACTIONS BREAKDOWN WITH STREAM FILTER ─────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Financial Transaction Ledger',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      '${filteredTx.length} records in view',
                      style: TextStyle(fontSize: 15.5, color: textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Stream Filter Chips
                FilterTabs(
                  tabs: const [
                    ('All Streams', 'All'),
                    ('Renewal Dues', 'Renewal dues'),
                    ('New Membership', 'New members'),
                    ('CTI Courses', 'Courses'),
                    ('Other', 'Other'),
                  ],
                  selected: _financialStreamFilter,
                  onSelected: (f) => setState(() => _financialStreamFilter = f),
                ),
                const SizedBox(height: 12),

                if (filteredTx.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No payments in this list',
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredTx.length > 8 ? 8 : filteredTx.length,
                    separatorBuilder: (c, i) => Divider(height: 1, color: border),
                    itemBuilder: (context, index) {
                      final tx = filteredTx[index] is Map<String, dynamic>
                          ? filteredTx[index]
                          : Map<String, dynamic>.from(filteredTx[index]);
                      final status = tx['status']?.toString().toLowerCase() ?? 'pending';
                      final isPaid = status == 'paid' || status == 'success' || status == 'completed';
                      final statusColor = isPaid
                          ? _kGreen
                          : (status == 'pending' ? _kAmber : _kRed);

                      final cat = _classifyTransactionCategory(tx);
                      Color catColor = _kBrown;
                      if (cat == 'Annual Renewal') catColor = _kGreen;
                      if (cat == 'New Membership') catColor = _kOrange;
                      if (cat == 'CTI Courses') catColor = _kAmber;

                      final amt = double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0;
                      final date = tx['date']?.toString() ?? tx['created_at']?.toString() ?? '';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: catColor.withAlpha(isDark ? 35 : 18),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                cat == 'Annual Renewal'
                                    ? Icons.autorenew_rounded
                                    : (cat == 'New Membership'
                                        ? Icons.person_add_alt_1_rounded
                                        : (cat == 'CTI Courses'
                                            ? Icons.school_rounded
                                            : Icons.receipt_long_rounded)),
                                size: 16,
                                color: catColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          tx['member_name']?.toString() ?? 'Anonymous Member',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17,
                                            color: textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: catColor.withAlpha(20),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          cat.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: catColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${tx['description'] ?? 'Platform Fee'} ${date.isNotEmpty ? '• ${date.split('T')[0]}' : ''}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: textMuted,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'GH₵ ${_formatCurrency(amt)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamCard({
    required String title,
    required String subtitle,
    required double amount,
    required String percentage,
    required int count,
    required IconData icon,
    required Color color,
    required String countSuffix,
    required bool isDark,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return Container(
      padding: const EdgeInsets.all(CubagSpace.md),
      decoration: BoxDecoration(
        color: CubagColors.paper,
        borderRadius: BorderRadius.circular(CubagRadius.card),
        border: Border.all(color: CubagColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: CubagSpace.xs),
              Expanded(child: Text(title, style: CubagType.label, overflow: TextOverflow.ellipsis)),
              Text('$percentage%', style: CubagType.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: CubagSpace.xs),
          Text(
            'GH₵ ${_formatCurrency(amount)}',
            style: CubagType.title.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 2),
          Text('$count $countSuffix', style: CubagType.caption),
        ],
      ),
    );
  }

  Widget _buildBankSettlementSection(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
    Color innerBg,
  ) {
    final bankMap = _filteredBankRevenue;
    final totalRev = _filteredRevenue > 0 ? _filteredRevenue : 1.0;

    final gcb = bankMap['107113005326']!;
    final zenith = bankMap['6010309212']!;
    final ecobank = bankMap['1441002452360']!;
    final nib = bankMap['1110045585101']!;

    final gcbAmt = gcb['amount'] as double;
    final zenithAmt = zenith['amount'] as double;
    final ecobankAmt = ecobank['amount'] as double;
    final nibAmt = nib['amount'] as double;

    final gcbPct = (gcbAmt / totalRev * 100).clamp(0, 100).toStringAsFixed(1);
    final zenithPct = (zenithAmt / totalRev * 100).clamp(0, 100).toStringAsFixed(1);
    final ecobankPct = (ecobankAmt / totalRev * 100).clamp(0, 100).toStringAsFixed(1);
    final nibPct = (nibAmt / totalRev * 100).clamp(0, 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 20 : 4),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CubagColors.action.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: CubagColors.action,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revenue by Bank Account',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      'How funds settle across CUBAG institutional bank accounts via payment codes.',
                      style: TextStyle(
                        fontSize: 16,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: CubagColors.action.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CubagColors.action.withAlpha(40)),
                ),
                child: const Text(
                  '4 Active Accounts',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: CubagColors.action,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4 Bank Cards Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 750;
              final cards = [
                _buildBankCard(gcb, gcbPct, isDark, textPrimary, textMuted),
                _buildBankCard(zenith, zenithPct, isDark, textPrimary, textMuted),
                _buildBankCard(ecobank, ecobankPct, isDark, textPrimary, textMuted),
                _buildBankCard(nib, nibPct, isDark, textPrimary, textMuted),
              ];

              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: cards
                          .map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: c)))
                          .toList(),
                    )
                  : Column(
                      children: cards
                          .map((c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: c))
                          .toList(),
                    );
            },
          ),
          const SizedBox(height: 16),

          // Multi-Segmented Proportional Distribution Bar for Banks
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Bank settlement share',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textMuted,
                    ),
                  ),
                  Text(
                    'Official payment codes',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textMuted.withAlpha(180),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      if (gcbAmt > 0)
                        Expanded(
                          flex: (gcbAmt * 100).toInt(),
                          child: Container(color: gcb['color'] as Color),
                        ),
                      if (zenithAmt > 0)
                        Expanded(
                          flex: (zenithAmt * 100).toInt(),
                          child: Container(color: zenith['color'] as Color),
                        ),
                      if (ecobankAmt > 0)
                        Expanded(
                          flex: (ecobankAmt * 100).toInt(),
                          child: Container(color: ecobank['color'] as Color),
                        ),
                      if (nibAmt > 0)
                        Expanded(
                          flex: (nibAmt * 100).toInt(),
                          child: Container(color: nib['color'] as Color),
                        ),
                      if (gcbAmt == 0 && zenithAmt == 0 && ecobankAmt == 0 && nibAmt == 0)
                        Expanded(
                          child: Container(color: isDark ? const Color(0xFF3D261C) : CubagColors.line),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _buildLegendItem('GCB Bank ($gcbPct%)', gcb['color'] as Color, textMuted),
                  _buildLegendItem('Zenith Bank ($zenithPct%)', zenith['color'] as Color, textMuted),
                  _buildLegendItem('Ecobank ($ecobankPct%)', ecobank['color'] as Color, textMuted),
                  _buildLegendItem('NIB ($nibPct%)', nib['color'] as Color, textMuted),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBankCard(
    Map<String, dynamic> bank,
    String percentage,
    bool isDark,
    Color textPrimary,
    Color textMuted,
  ) {
    final amt = bank['amount'] as double;
    final color = bank['color'] as Color;
    final codes = (bank['codes'] as List<String>);
    final count = bank['count'] as int;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? CubagColors.ink : CubagColors.sand.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(isDark ? 60 : 40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(bank['icon'] as IconData, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bank['name'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Acc: ',
                style: TextStyle(fontSize: 11.5, color: textMuted, fontWeight: FontWeight.w500),
              ),
              SelectableText(
                bank['account'] as String,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: bank['account'] as String));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied ${bank['name']} account number: ${bank['account']}'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Icon(Icons.copy_rounded, size: 12, color: textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            bank['purpose'] as String,
            style: TextStyle(fontSize: 11, color: textMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: codes.map((c) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: color.withAlpha(15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withAlpha(30)),
              ),
              child: Text(
                c,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            'GH₵ ${_formatCurrency(amt)}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count payment${count == 1 ? '' : 's'} settled',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, Color textMuted) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: textMuted,
          ),
        ),
      ],
    );
  }

  Widget _financialMetricBar(
    String label,
    double val,
    Color color,
    bool isDark,
    Color textPrimary,
    Color textMuted,
  ) {
    final total =
        _filteredRevenue + _filteredPendingRevenue + _filteredFailedRevenue;
    final pct = total > 0 ? val / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textMuted,
                ),
              ),
              Text(
                _cedis(val),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: isDark ? const Color(0xFF4D2D20) : Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembershipTab(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
    Color innerBg,
  ) {
    final typeColors = {
      'Licentiate': _kOrange,
      'Associate': _kGreen,
      'Corporate': _kBrown,
    };

    final statusColors = {
      'active': _kGreen,
      'pending': _kAmber,
      'suspended': _kRed,
      'inactive': textMuted,
    };

    final filteredStatus = _filteredStatusCountsMap;
    final filteredTypes = _filteredTypeCountsMap;
    final filteredTotal = _filteredTotalMembersCount;

    return SingleChildScrollView(
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Member Status Ratios',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _CustomRingChart(
                    data: filteredStatus,
                    colors: statusColors,
                    isDark: isDark,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Member Classifications',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...filteredTypes.entries.map((e) {
                    final color = typeColors[e.key] ?? textMuted;
                    final maxCount = filteredTotal > 0
                        ? filteredTotal.toDouble()
                        : 10.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                e.key,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: textMuted,
                                ),
                              ),
                              Text(
                                '${e.value.toInt()}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: e.value / maxCount,
                              minHeight: 8,
                              backgroundColor: isDark ? const Color(0xFF4D2D20) : Colors.grey.shade100,
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsTab(
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
    Color innerBg,
  ) {
    return SingleChildScrollView(
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _activityMetricCard(
                  'Push Alerts Dispatched',
                  '$_announcementsCount Alerts',
                  Icons.campaign,
                  _kOrange,
                  isDark,
                  cardBg,
                  border,
                  textPrimary,
                  textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _activityMetricCard(
                  'Open Support Tickets',
                  '$_openTickets Open',
                  Icons.support_agent,
                  _kRed,
                  isDark,
                  cardBg,
                  border,
                  textPrimary,
                  textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _activityMetricCard(
                  'Logistics Vanning Logs',
                  '$_cargoSchedulesCount Logs',
                  Icons.local_shipping,
                  _kBrown,
                  isDark,
                  cardBg,
                  border,
                  textPrimary,
                  textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activityMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
    Color cardBg,
    Color border,
    Color textPrimary,
    Color textMuted,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.25 : 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final double maxValue;
  final Color color;
  final bool isDark;
  final Color textMuted;

  const _CustomBarChart({
    required this.values,
    required this.labels,
    required this.maxValue,
    this.color = _kOrange,
    required this.isDark,
    required this.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 190,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue * 1.2,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${labels[group.x]}\n',
                  TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  children: <TextSpan>[
                    TextSpan(
                      text: '₵${rod.toY.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      labels[idx],
                      style: TextStyle(
                        color: textMuted,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  );
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox.shrink();
                  final valStr = value >= 1000
                      ? '${(value / 1000).toStringAsFixed(1)}k'
                      : value.toStringAsFixed(0);
                  return Text(
                    '₵$valStr',
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: isDark ? const Color(0xFF4D2D20) : Colors.grey.withValues(alpha: 0.2),
              strokeWidth: 1,
              dashArray: [5, 5],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(values.length, (index) {
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: values[index],
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.6), color],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _CustomRingChart extends StatefulWidget {
  final Map<String, double> data;
  final Map<String, Color> colors;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;

  const _CustomRingChart({
    required this.data,
    required this.colors,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
  });

  @override
  State<_CustomRingChart> createState() => _CustomRingChartState();
}

class _CustomRingChartState extends State<_CustomRingChart> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final total = widget.data.values.fold(0.0, (sum, val) => sum + val);
    final entries = widget.data.entries.toList();

    return Row(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            children: [
              PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          touchedIndex = -1;
                          return;
                        }
                        touchedIndex = pieTouchResponse
                            .touchedSection!
                            .touchedSectionIndex;
                      });
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  sectionsSpace: 0,
                  centerSpaceRadius: 40,
                  sections: total == 0
                      ? [
                          PieChartSectionData(
                            color: widget.isDark ? const Color(0xFF4D2D20) : Colors.grey.shade200,
                            value: 1,
                            showTitle: false,
                            radius: 12,
                          ),
                        ]
                      : List.generate(entries.length, (i) {
                          final isTouched = i == touchedIndex;
                          final radius = isTouched ? 18.0 : 12.0;
                          final color =
                              widget.colors[entries[i].key] ?? Colors.grey;

                          return PieChartSectionData(
                            color: color,
                            value: entries[i].value,
                            title: '',
                            radius: radius,
                          );
                        }),
                ),
              ),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.textMuted,
                      ),
                    ),
                    Text(
                      '${total.toInt()}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: widget.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: entries.map((e) {
              final color = widget.colors[e.key] ?? Colors.grey;
              final pct = total > 0
                  ? (e.value / total * 100).toStringAsFixed(1)
                  : '0';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e.key.toUpperCase()}: ${e.value.toInt()} ($pct%)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: widget.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
