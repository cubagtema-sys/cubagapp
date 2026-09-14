import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../components/app_layout.dart';
import '../components/admin_components.dart';
import '../components/custom_dropdown.dart';
import '../components/skeleton_loader.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import '../utils/file_download.dart';

const _kOrange = Color(0xFFFF5000);
const _kGreen = Color(0xFF10B981);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFD97706);
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

  bool _isWithinDateRange(String? dateStr) {
    if (dateStr == null) return false;
    final date = DateTime.tryParse(dateStr);
    if (date == null) return false;

    final now = DateTime.now();
    switch (_dateFilter) {
      case 'Last 7 Days':
        final limit = now.subtract(const Duration(days: 7));
        return date.isAfter(limit);
      case 'Last 30 Days':
        final limit = now.subtract(const Duration(days: 30));
        return date.isAfter(limit);
      case 'Year to Date':
        final startOfYear = DateTime(now.year, 1, 1);
        return date.isAfter(startOfYear) || date.isAtSameMomentAs(startOfYear);
      case 'All Time':
      default:
        return true;
    }
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
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
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
          builder: (context) => AlertDialog(
            title: Text('Export $title'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Copy the spreadsheet data below:',
                  style: GoogleFonts.outfit(fontSize: 16),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 150,
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      csvContent,
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showExportDialog(bool isDark, Color cardBg, Color textPrimary, Color textMuted) {
    final borderCol = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kOrange.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.table_chart_rounded, color: _kOrange, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export Spreadsheet',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 21, color: textPrimary),
                  ),
                  Text(
                    'Microsoft Excel & CSV Compatible',
                    style: GoogleFonts.inter(color: _kGreen, fontSize: 15.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select the dataset you would like to export. Files include full metadata and UTF-8 formatting ready for Excel.',
              style: GoogleFonts.inter(color: textMuted, fontSize: 17),
            ),
            const SizedBox(height: 16),
            // Financial Ledger Button Card
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _exportFinancialsCSV();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderCol),
                  color: _kOrange.withAlpha(15),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded, color: _kOrange, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Financial Ledger Export',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: textPrimary),
                          ),
                          Text(
                            '${_transactions.length} payment records, MoMo & Card receipts',
                            style: GoogleFonts.inter(fontSize: 15.5, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.download_rounded, color: _kOrange, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Members Roster Button Card
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _exportMembersCSV();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderCol),
                  color: _kBrown.withAlpha(15),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_alt_rounded, color: _kBrown, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Members Roster Export',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: textPrimary),
                          ),
                          Text(
                            '${_rawMembers.length} member profiles, categories & licenses',
                            style: GoogleFonts.inter(fontSize: 15.5, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.download_rounded, color: _kBrown, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.outfit(color: textMuted, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _exportFinancialsCSV() {
    final filteredTx = _transactions
        .where(
          (tx) => _isWithinDateRange(
            tx['date']?.toString() ?? tx['created_at']?.toString(),
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
    _exportCSV('CUBAG_Financial_Ledger_${_dateFilter.replaceAll(' ', '_')}', buffer.toString());
  }

  void _exportMembersCSV() {
    final filteredMembers = _rawMembers.where((m) {
      final dateStr = m['created_at']?.toString() ?? m['date']?.toString();
      if (dateStr == null) return true;
      return _isWithinDateRange(dateStr);
    }).toList();
    final buffer = StringBuffer();
    buffer.writeln('Member ID,Full Name,Company,Email,Phone,Member Category,Port of Operation,License Number,TIN,Status,Compliance Score,Star Rating,Registration Date');
    
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
    _exportCSV('CUBAG_Members_Roster_${_dateFilter.replaceAll(' ', '_')}', buffer.toString());
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

    try {
      // Fetch Dashboard Stats
      final dashboardRes = await ApiService().get('/admin/dashboard');
      if (dashboardRes.statusCode == 200 && dashboardRes.data is Map) {
        final dData = dashboardRes.data as Map<String, dynamic>;
        final kpis = dData['kpis'] as Map<String, dynamic>? ?? {};
        _totalMembers =
            (kpis['total_members'] ?? kpis['members_count'] ?? 0) as int;
        _openTickets =
            (kpis['open_tickets'] ?? kpis['tickets_count'] ?? 0) as int;
      }

      // Fetch Financial Stats
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
              AppLogger.error('admin_analytics_page', e, st);
            }
          }
        }
      }

      // Fetch Members Stats
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
      }

      // Fetch cargo schedules (for Operations Tab)
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

      // Fetch announcements (for Operations Tab)
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
    } catch (e, st) {
      AppLogger.error('admin_analytics_page _fetchData', e, st);
      _error =
          'Failed to fetch some analytics data. Visualizing available records.';
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF281710) : Colors.white;
    final border = isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF64748B);
    final innerBg = isDark ? const Color(0xFF1A0F0A) : const Color(0xFFF1F5F9);

    return AppLayout(
      title: 'Platform Analytics',
      hideSearch: false,
      scrollable: true,
      child: _loading
          ? const DashboardSkeleton()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x19ef4444),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x33ef4444)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFef4444),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                          _error!,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFFef4444),
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.refresh,
                            color: Color(0xFFef4444),
                            size: 18,
                          ),
                          onPressed: _fetchData,
                        ),
                      ],
                    ),
                  ),

                AdminHeader(
                  title: 'Platform Analytics & Business Intelligence',
                  subtitle:
                      'Real-time financial performance telemetry, membership demographics, and service metrics.',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: () => _showExportDialog(isDark, cardBg, textPrimary, textMuted),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(
                        'Export Ledger',
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kOrange,
                        side: const BorderSide(color: _kOrange),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CustomDropdown<String>(
                      value: _dateFilter,
                      width: 140,
                      dense: true,
                      items: const [
                        DropdownItem(value: 'All Time', label: 'All Time'),
                        DropdownItem(
                          value: 'Last 7 Days',
                          label: 'Last 7 Days',
                        ),
                        DropdownItem(
                          value: 'Last 30 Days',
                          label: 'Last 30 Days',
                        ),
                        DropdownItem(
                          value: 'Year to Date',
                          label: 'Year to Date',
                        ),
                      ],
                      onChanged: (newValue) {
                        setState(() {
                          _dateFilter = newValue;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Top Stats Summary Grid
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    return GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: isMobile ? 2 : 4,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: isMobile ? 1.4 : 1.8,
                      children: [
                        AdminStatCard(
                          label: 'Total Revenue',
                          value: '₵${_filteredRevenue.toStringAsFixed(0)}',
                          icon: Icons.payments_rounded,
                          color: _kGreen,
                        ),
                        AdminStatCard(
                          label: 'Total Members',
                          value: '$_filteredTotalMembersCount',
                          icon: Icons.people_alt_rounded,
                          color: _kBrown,
                        ),
                        AdminStatCard(
                          label: 'Cargo Logs',
                          value: '$_cargoSchedulesCount',
                          icon: Icons.local_shipping_rounded,
                          color: _kOrange,
                        ),
                        AdminStatCard(
                          label: 'Open Tickets',
                          value: '$_openTickets',
                          icon: Icons.support_agent_rounded,
                          color: _kRed,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Tab Bar
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: border),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: _kOrange,
                    unselectedLabelColor: isDark ? Colors.white70 : const Color(0xFF64748B),
                    indicatorColor: _kOrange,
                    indicatorWeight: 3,
                    labelStyle: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    tabs: const [
                      Tab(text: 'Financial Center'),
                      Tab(text: 'Membership Insights'),
                      Tab(text: 'Operations & Alerts'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tab Body
                SizedBox(
                  height: 980,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFinancialTab(isDark, cardBg, border, textPrimary, textMuted, innerBg),
                      _buildMembershipTab(isDark, cardBg, border, textPrimary, textMuted, innerBg),
                      _buildOperationsTab(isDark, cardBg, border, textPrimary, textMuted, innerBg),
                    ],
                  ),
                ),
              ],
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
    final sortedMonths = filteredMonthly.keys.toList()..sort();
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
                            'Financial Revenue Stream Breakdown',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            'Comprehensive collection audit across Renewals, New Membership Dues, and CTI Courses',
                            style: GoogleFonts.inter(
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
                        style: GoogleFonts.outfit(
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
                                  title: 'Annual Renewal Dues',
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
                                  title: 'New Membership',
                                  subtitle: 'Dossiers & entrance dues',
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
                                  title: 'CTI Training Courses',
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
                                  title: 'Other Platform Fees',
                                  subtitle: 'ID Cards, badges & misc',
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
                                title: 'Annual Renewal Dues',
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
                                title: 'New Membership Dues',
                                subtitle: 'Dossiers & entrance dues',
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
                                title: 'CTI Training Courses',
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
                                title: 'Other Platform Fees',
                                subtitle: 'ID Cards, badges & misc',
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
                          'Revenue Stream Proportions',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textMuted,
                          ),
                        ),
                        Text(
                          '100% of Verified Collections',
                          style: GoogleFonts.inter(
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
                                child: Container(color: isDark ? const Color(0xFF4D2D20) : const Color(0xFFE2E8F0)),
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
                        _buildLegendItem('Renewal Dues ($renewalPct%)', _kGreen, textMuted),
                        _buildLegendItem('New Membership ($newMemPct%)', _kOrange, textMuted),
                        _buildLegendItem('CTI Courses ($coursePct%)', _kAmber, textMuted),
                        _buildLegendItem('Other Services ($otherPct%)', _kBrown, textMuted),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                        'Revenue Collection Trend (GH₵)',
                        style: GoogleFonts.outfit(
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
                                      style: GoogleFonts.outfit(
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
                        'Dues Settlement Status',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _financialMetricBar(
                        'Paid Revenue',
                        _filteredRevenue,
                        _kGreen,
                        isDark,
                        textPrimary,
                        textMuted,
                      ),
                      _financialMetricBar(
                        'Pending Receivables',
                        _filteredPendingRevenue,
                        _kAmber,
                        isDark,
                        textPrimary,
                        textMuted,
                      ),
                      _financialMetricBar(
                        'Failed/Overdue Dues',
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
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      '${filteredTx.length} records in view',
                      style: GoogleFonts.inter(fontSize: 15.5, color: textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Stream Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      'All Streams',
                      'Renewal Dues',
                      'New Membership',
                      'CTI Courses',
                      'Other',
                    ].map((filter) {
                      final isSelected = _financialStreamFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            filter,
                            style: GoogleFonts.outfit(
                              fontSize: 15.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: _kOrange,
                          backgroundColor: isDark ? const Color(0xFF4D2D20) : const Color(0xFFF1F5F9),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _financialStreamFilter = filter);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                if (filteredTx.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No transaction records found matching the filter criteria',
                        style: GoogleFonts.outfit(
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
                                          style: GoogleFonts.outfit(
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
                                          style: GoogleFonts.outfit(
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
                                    style: GoogleFonts.inter(
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
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 17,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  status.toUpperCase(),
                                  style: GoogleFonts.outfit(
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 25 : 10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(isDark ? 60 : 45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$percentage%',
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'GH₵ ${_formatCurrency(amount)}',
            style: GoogleFonts.outfit(
              fontSize: 19.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count $countSuffix',
            style: GoogleFonts.inter(
              fontSize: 14.5,
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
          style: GoogleFonts.inter(
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
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textMuted,
                ),
              ),
              Text(
                '₵${val.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
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
                    'Broker Classifications',
                    style: GoogleFonts.outfit(
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
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: textMuted,
                                ),
                              ),
                              Text(
                                '${e.value.toInt()}',
                                style: GoogleFonts.outfit(
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
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.outfit(
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
                  GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  children: <TextSpan>[
                    TextSpan(
                      text: '₵${rod.toY.toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
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
                      style: GoogleFonts.outfit(
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
                    style: GoogleFonts.outfit(
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
                      'TOTAL',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '${total.toInt()}',
                      style: GoogleFonts.outfit(
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
                          style: GoogleFonts.outfit(
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
