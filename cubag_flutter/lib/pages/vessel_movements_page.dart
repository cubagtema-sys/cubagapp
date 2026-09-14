import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/app_layout.dart';
import '../components/iframe_widget.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';

class VesselMovementsPage extends StatefulWidget {
  const VesselMovementsPage({super.key});
  @override
  State<VesselMovementsPage> createState() => _VesselMovementsPageState();
}

class _VesselMovementsPageState extends State<VesselMovementsPage> {
  // Registry fetched from backend — no hardcoded vessel data in the app
  List<Map<String, dynamic>> _registryVessels = [];

  final Map<String, dynamic> _vesselsMap = {};
  String _search = '';
  bool _loading = true;
  bool _showSuggestions = false;
  final FocusNode _focusNode = FocusNode();
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: _search);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              _showSuggestions = false;
            });
          }
        });
      } else {
        setState(() {
          _showSuggestions = true;
        });
      }
    });
    _fetch();
    _initSocketListener();
  }

  void _onSocketConnect(dynamic _) {
    if (mounted) setState(() {});
  }

  void _onSocketDisconnect(dynamic _) {
    if (mounted) setState(() {});
  }

  void _initSocketListener() {
    final socket = SocketService().socket;
    if (socket != null) {
      socket.off('vessel_update', _onVesselUpdate);
      socket.off('connect', _onSocketConnect);
      socket.off('disconnect', _onSocketDisconnect);

      socket.on('vessel_update', _onVesselUpdate);
      socket.on('connect', _onSocketConnect);
      socket.on('disconnect', _onSocketDisconnect);
    }
  }

  void _onVesselUpdate(dynamic data) {
    if (!mounted) return;
    setState(() {
      final mmsi = data['mmsi']?.toString();
      if (mmsi != null) {
        _vesselsMap[mmsi] = data;
      }
    });
  }

  Future<void> _fetch() async {
    if (!_loading) setState(() => _loading = true);
    try {
      // Fetch live AIS vessels
      final res = await ApiService().get('/vessels');
      if (res.statusCode == 200) {
        final list = ApiService.ensureList(res.data);
        setState(() {
          for (var item in list) {
            final mmsi = item['mmsi']?.toString();
            if (mmsi != null) {
              _vesselsMap[mmsi] = item;
            }
          }
        });
      }
      // Fetch registry for autocomplete suggestions
      final regRes = await ApiService().get('/vessels/registry');
      if (regRes.statusCode == 200) {
        final regList = List<Map<String, dynamic>>.from(
          ApiService.ensureList(
            regRes.data,
          ).map((e) => Map<String, dynamic>.from(e)),
        );
        if (mounted) setState(() => _registryVessels = regList);
      }
    } catch (e, st) {
      AppLogger.error('vessel_movements_page', e, st);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    final socket = SocketService().socket;
    if (socket != null) {
      socket.off('vessel_update', _onVesselUpdate);
      socket.off('connect', _onSocketConnect);
      socket.off('disconnect', _onSocketDisconnect);
    }
    super.dispose();
  }

  Widget _buildDetailRow(String label, dynamic value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: isDark ? Colors.white60 : const Color(0xFF64748b),
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value?.toString() ?? '—',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF281710),
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final socket = SocketService().socket;
    final isConnected = socket?.connected ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1A0F0A) : Colors.white;

    // Convert map to list and sort by last_update descending
    final vesselList = _vesselsMap.values.toList();
    vesselList.sort((a, b) {
      final dateA =
          DateTime.tryParse(a['last_update']?.toString() ?? '') ??
          DateTime(1970);
      final dateB =
          DateTime.tryParse(b['last_update']?.toString() ?? '') ??
          DateTime(1970);
      return dateB.compareTo(dateA);
    });

    // Restrict list to vessels related to Tema only (departure or destination)
    final filtered = vesselList.where((v) {
      final q = _search.toLowerCase();

      // Basic search matching (name, mmsi, destination)
      final matchesSearch =
          (v['name'] ?? '').toString().toLowerCase().contains(q) ||
          (v['mmsi'] ?? '').toString().contains(q) ||
          (v['destination'] ?? '').toString().toLowerCase().contains(q);

      // Only include vessels where departure port or destination mentions "tema"
      final departure = (v['departure_port'] ?? v['port_of_operation'] ?? '')
          .toString()
          .toLowerCase();
      final destination = (v['destination'] ?? '').toString().toLowerCase();
      final isTema = departure.contains('tema') || destination.contains('tema');

      // If the user has typed a search query, require both Tema match and the query match.
      // If no search query, show all Tema-related vessels.
      return isTema && (q.isEmpty ? true : matchesSearch);
    }).toList();

    final suggestions = _registryVessels
        .where((v) {
          final q = _search.toLowerCase();
          return (v['name'] ?? '').toString().toLowerCase().contains(q) ||
              (v['mmsi'] ?? '').toString().contains(q);
        })
        .take(5)
        .toList();

    final isMmsi = RegExp(r'^\d{9}$').hasMatch(_search);
    Map<String, dynamic>? activeVessel;
    if (isMmsi) {
      activeVessel = _vesselsMap[_search] != null
          ? Map<String, dynamic>.from(_vesselsMap[_search]!)
          : null;
      final common = _registryVessels.firstWhere(
        (item) => item['mmsi']?.toString() == _search,
        orElse: () => {},
      );
      if (activeVessel == null && common.isNotEmpty) {
        // Registry data only — no live AIS yet. Show static specs, no fake operational data.
        activeVessel = {
          'mmsi': common['mmsi'],
          'name': common['name'],
          'type': common['type'],
          'flag': common['flag']?.toString().toUpperCase(),
          'imo': common['imo'],
          'callsign': common['callsign'],
          'length': common['length'],
          'width': common['width'],
          'status': 'Awaiting AIS Signal',
          'speed': null,
          'destination': common['destination'],
          'eta': common['eta'],
          'departure_port': common['departure_port'],
          'atd': common['atd'],
        };
      } else if (activeVessel != null && common.isNotEmpty) {
        // Merge missing static/voyage data from registry into the live AIS feed!
        activeVessel['departure_port'] =
            activeVessel['departure_port'] ?? common['departure_port'];
        activeVessel['atd'] = activeVessel['atd'] ?? common['atd'];
        activeVessel['length'] = activeVessel['length'] ?? common['length'];
        activeVessel['width'] = activeVessel['width'] ?? common['width'];

        // Destination/ETA from AIS might be empty string or '—', prefer registry if AIS is missing it.
        if (activeVessel['destination'] == null ||
            activeVessel['destination'] == '—' ||
            activeVessel['destination'].toString().isEmpty) {
          activeVessel['destination'] = common['destination'];
        }
        if (activeVessel['eta'] == null ||
            activeVessel['eta'] == '—' ||
            activeVessel['eta'].toString().isEmpty) {
          activeVessel['eta'] = common['eta'];
        }
      }
    }

    // Connection Status Bar widget
    final connectionWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isConnected
            ? primary.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.05),
        border: Border.all(
          color: isConnected
              ? primary.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.15),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            color: isConnected ? primary : Colors.grey,
            size: 10,
          ),
          const SizedBox(width: 8),
          Text(
            isConnected ? 'Live AIS Stream Connected' : 'Connecting to AIS...',
            style: GoogleFonts.outfit(
              color: isConnected ? primary : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            isMmsi ? '1 vessel tracked' : '${filtered.length} vessels',
            style: GoogleFonts.inter(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );

    // Search Bar TextField
    final searchWidget = TextField(
      focusNode: _focusNode,
      controller: _searchController,
      onChanged: (v) {
        setState(() => _search = v);
        if ((RegExp(r'^\d{9}$').hasMatch(v) || v.length > 6) &&
            socket != null) {
          socket.emit('track_vessel', {'mmsi': v});
        }
      },
      style: GoogleFonts.inter(
        fontSize: 16,
        color: isDark ? Colors.white : const Color(0xFF1A0F0A),
      ),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
        hintText: 'Search by vessel name, MMSI or destination...',
        hintStyle: GoogleFonts.inter(
          fontSize: 15,
          color: const Color(0xFF94a3b8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF1A0F0A) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    _search = '';
                    _searchController.text = '';
                  });
                },
              )
            : null,
      ),
    );

    // Suggestion box widget
    final suggestionBox =
        _showSuggestions && _search.length > 1 && suggestions.isNotEmpty
        ? Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A0F0A) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: suggestions.length,
              itemBuilder: (context, i) {
                final v = suggestions[i];
                return InkWell(
                  onTap: () {
                    final mmsi = v['mmsi']!;
                    setState(() {
                      _search = mmsi;
                      _searchController.text = mmsi;
                      _searchController.selection = TextSelection.fromPosition(
                        TextPosition(offset: mmsi.length),
                      );
                      _showSuggestions = false;
                      _focusNode.unfocus();
                    });
                    if (socket != null) {
                      socket.emit('track_vessel', {'mmsi': mmsi});
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: i < suggestions.length - 1
                          ? Border(
                              bottom: BorderSide(
                                color: Theme.of(context).dividerColor,
                              ),
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v['name']!,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A0F0A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'MMSI: ${v['mmsi']}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: primary,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        : const SizedBox.shrink();

    // Voyage Card details view (live details view)
    Widget buildVoyageDetails() {
      if (activeVessel == null) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.directions_boat_rounded,
                            color: primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activeVessel['name']?.toString() ??
                                  'Detecting Vessel...',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A0F0A),
                              ),
                            ),
                            Text(
                              'MMSI: ${activeVessel['mmsi']} · IMO: ${activeVessel['imo'] ?? 'N/A'}',
                              style: GoogleFonts.inter(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF10b981,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                activeVessel['status']
                                        ?.toString()
                                        .toUpperCase() ??
                                    'UNDERWAY',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF10b981),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),

                // Route/Ports Info
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DEPARTURE PORT',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            activeVessel['departure_port']?.toString() ?? '—',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF281710),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activeVessel['atd'] != null
                                ? 'ATD: ${activeVessel['atd']}'
                                : '📡 Awaiting AIS...',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.trending_flat_rounded, color: primary, size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'REPORTED DESTINATION',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            activeVessel['destination']?.toString() ??
                                'Detecting via AIS...',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF281710),
                            ),
                            textAlign: TextAlign.end,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ETA: ${activeVessel['eta']?.toString() ?? 'Awaiting Signal...'}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Summary
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.05),
                  primary.withValues(alpha: 0.01),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primary.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Voyage Summary',
                      style: GoogleFonts.outfit(
                        color: primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'The cargo ship ${activeVessel['name']} is currently located in the '
                  '${activeVessel['region'] ?? 'Ghana Coastal Waters'} (last reported '
                  '${activeVessel['last_update'] != null ? "recently" : "moments ago"}).\n\n'
                  '${activeVessel['name']} (IMO: ${activeVessel['imo'] ?? 'N/A'}) is a '
                  '${activeVessel['type'] ?? 'Container Ship'} sailing under the flag of '
                  '${activeVessel['flag'] ?? 'N/A'}. Her length overall (LOA) is '
                  '${activeVessel['length'] ?? '—'} meters and her width is '
                  '${activeVessel['width'] ?? '—'} meters.',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.5,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Technical specifications grid (AIS telemetry removed as requested)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'General Specifications',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF1A0F0A),
                  ),
                ),
                const SizedBox(height: 12),
                _buildDetailRow('Vessel Name', activeVessel['name']),
                _buildDetailRow('Flag', activeVessel['flag']),
                _buildDetailRow('IMO Number', activeVessel['imo']),
                _buildDetailRow('MMSI', activeVessel['mmsi']),
                _buildDetailRow('Call Sign', activeVessel['callsign']),
                _buildDetailRow('Vessel Type', activeVessel['type']),
                _buildDetailRow(
                  'Dimensions',
                  '${activeVessel['length'] ?? '—'}m x ${activeVessel['width'] ?? '—'}m',
                ),
              ],
            ),
          ),
        ],
      );
    }

    return AppLayout(
      title: 'Vessels',
      scrollable: false,
      child: RefreshIndicator(
        onRefresh: _fetch,
        color: primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 24.0,
                ),
                child: Column(
                  children: [
                    // Status bar
                    connectionWidget,
                    const SizedBox(height: 16),

                    // Search and Suggestions
                    searchWidget,
                    suggestionBox,
                    const SizedBox(height: 16),

                    // Detail View OR Main List
                    if (isMmsi) ...[
                      // Back to List link
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _search = '';
                              _searchController.text = '';
                            });
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: Text(
                            'Back to Live List',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Map Container
                      Container(
                        height: 320,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                            width: 1.5,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: IframeWidget(mmsi: _search),
                      ),
                      const SizedBox(height: 16),

                      buildVoyageDetails(),
                    ] else ...[
                      // Shimmer loading state
                      if (_loading)
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 6,
                          separatorBuilder: (ctx, i) =>
                              const SizedBox(height: 16),
                          itemBuilder: (ctx, i) => const ShimmerListTile(),
                        )
                      // Empty state view
                      else if (filtered.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 48,
                            horizontal: 24,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.sailing_rounded,
                                  size: 36,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Vessels In Range',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1A0F0A),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _search.isNotEmpty
                                    ? 'Try modifying your search keywords.'
                                    : 'Waiting for live AIS data from the Gulf of Guinea...',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  color: const Color(0xFF64748b),
                                ),
                              ),
                            ],
                          ),
                        )
                      // Vessel list cards
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final v = filtered[index];
                            final doubleSpeed = double.tryParse(
                              v['speed']?.toString() ?? '0',
                            );
                            final isUnderway =
                                doubleSpeed != null && doubleSpeed > 0;
                            final speedColor = isUnderway
                                ? const Color(0xFF10b981)
                                : Colors.amber;
                            final speedText = isUnderway
                                ? '${v['speed']} kn'
                                : 'At Anchor';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          v['mmsi'] != null
                                              ? Icons.directions_boat_rounded
                                              : Icons.local_shipping_rounded,
                                          color: primary,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              v['name']?.toString() ??
                                                  v['vessel']?.toString() ??
                                                  'Unnamed Vessel',
                                              style: GoogleFonts.outfit(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 17,
                                                color: isDark
                                                    ? Colors.white
                                                    : const Color(0xFF1A0F0A),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              v['mmsi'] != null
                                                  ? 'MMSI: ${v['mmsi']} · ${v['type'] ?? ''}'
                                                  : 'Container: ${v['container'] ?? 'N/A'}',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: const Color(0xFF64748b),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: speedColor.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              speedText,
                                              style: GoogleFonts.outfit(
                                                color: speedColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          if (v['last_update'] != null) ...[
                                            const SizedBox(height: 4),
                                            _buildUpdateTime(v['last_update']),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  _buildVoyageInfo(context, v),
                                  const SizedBox(height: 12),
                                  _buildBottomActions(v),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateTime(dynamic lastUpdate) {
    final localTime = DateTime.tryParse(lastUpdate.toString())?.toLocal();
    if (localTime == null) return const SizedBox.shrink();
    final timeStr =
        "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:${localTime.second.toString().padLeft(2, '0')}";
    return Text(
      timeStr,
      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
    );
  }

  Widget _buildVoyageInfo(BuildContext context, dynamic v) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0F0A) : const Color(0xFFf8fafc),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DESTINATION',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v['destination']?.toString() ?? 'N/A',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF281710),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ETA',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v['eta']?.toString() ?? 'N/A',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF281710),
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

  Widget _buildBottomActions(dynamic v) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              size: 14,
              color: Colors.grey.shade400,
            ),
            const SizedBox(width: 4),
            Text(
              'Pos: ${v['lat'] != null ? double.tryParse(v['lat'].toString())?.toStringAsFixed(4) : '0.0000'}, ${v['lng'] != null ? double.tryParse(v['lng'].toString())?.toStringAsFixed(4) : '0.0000'}',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _search = v['mmsi']?.toString() ?? '';
              _searchController.text = _search;
            });
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'View Details',
            style: GoogleFonts.outfit(
              color: Theme.of(context).primaryColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
