import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/iframe_widget.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../components/shimmer_loader.dart';
import '../utils/app_logger.dart';
import '../design/cubag_design.dart';

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

  static const _kBrown = Color(0xFF6B3E26);
  static const _kOrange = CubagColors.action;
  static const _kGreen = CubagColors.valid;
  static const _kAmber = CubagColors.due;

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

  Widget _buildDetailRow(
    String label,
    dynamic value,
    Color text,
    Color muted,
    Color border,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value?.toString() ?? '—',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: text,
                fontFeatures: const [FontFeature.tabularFigures()],
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
    final socket = SocketService().socket;
    final isConnected = socket?.connected ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E130D) : Colors.white;
    final border = isDark ? const Color(0xFF3D261C) : CubagColors.line;
    final text = isDark ? const Color(0xFFFFF8F3) : CubagColors.ink;
    final muted = isDark ? const Color(0xFFC8ADA0) : CubagColors.muted;
    final surfaceRaised = isDark ? const Color(0xFF281710) : const Color(0xFFFAF6F0);

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

      final departure = (v['departure_port'] ?? v['port_of_operation'] ?? '')
          .toString()
          .toLowerCase();
      final destination = (v['destination'] ?? '').toString().toLowerCase();
      final isTema = departure.contains('tema') || destination.contains('tema');

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
        activeVessel['departure_port'] =
            activeVessel['departure_port'] ?? common['departure_port'];
        activeVessel['atd'] = activeVessel['atd'] ?? common['atd'];
        activeVessel['length'] = activeVessel['length'] ?? common['length'];
        activeVessel['width'] = activeVessel['width'] ?? common['width'];

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isConnected ? _kGreen : muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isConnected ? 'Live AIS Stream Connected' : 'Connecting to AIS Feed...',
            style: TextStyle(
              color: isConnected ? text : muted,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          Text(
            isMmsi ? '1 vessel selected' : '${filtered.length} vessels in range',
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
      style: TextStyle(fontSize: 14, color: text),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search_rounded, color: muted, size: 18),
        hintText: 'Search by vessel name, MMSI or port...',
        hintStyle: TextStyle(fontSize: 13.5, color: muted.withValues(alpha: 0.7)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _kBrown, width: 1.5),
        ),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                tooltip: 'Clear',
                icon: Icon(Icons.clear_rounded, color: muted, size: 16),
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
              color: cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 1.0),
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
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: i < suggestions.length - 1
                          ? Border(bottom: BorderSide(color: border, width: 1.0))
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
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'MMSI: ${v['mmsi']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: muted,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: _kBrown,
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
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: border, width: 1.0),
                      ),
                      child: const Icon(
                        Icons.directions_boat_rounded,
                        color: _kBrown,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeVessel['name']?.toString() ?? 'Detecting Vessel...',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16.5,
                              color: text,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MMSI: ${activeVessel['mmsi']} · IMO: ${activeVessel['imo'] ?? 'N/A'}',
                            style: TextStyle(
                              color: muted,
                              fontSize: 12.5,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _kGreen.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _kGreen.withValues(alpha: 0.3),
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              activeVessel['status']?.toString().toUpperCase() ?? 'UNDERWAY',
                              style: const TextStyle(
                                color: _kGreen,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: border, height: 1.0),
                const SizedBox(height: 14),

                // Route/Ports Info
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Departure',
                            style: TextStyle(
                              fontSize: 11,
                              color: muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            activeVessel['departure_port']?.toString() ?? '—',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activeVessel['atd'] != null
                                ? 'ATD: ${activeVessel['atd']}'
                                : 'Awaiting AIS ATD',
                            style: TextStyle(
                              fontSize: 12,
                              color: muted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, color: _kBrown, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Destination',
                            style: TextStyle(
                              fontSize: 11,
                              color: muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            activeVessel['destination']?.toString() ?? 'Detecting via AIS...',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: text,
                            ),
                            textAlign: TextAlign.end,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ETA: ${activeVessel['eta']?.toString() ?? 'Awaiting Signal...'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: muted,
                              fontFeatures: const [FontFeature.tabularFigures()],
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
          const SizedBox(height: 14),

          // Technical specifications grid
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vessel Particulars',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: text,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),
                _buildDetailRow('Vessel Name', activeVessel['name'], text, muted, border),
                _buildDetailRow('Flag State', activeVessel['flag'], text, muted, border),
                _buildDetailRow('IMO Number', activeVessel['imo'], text, muted, border),
                _buildDetailRow('MMSI Identifier', activeVessel['mmsi'], text, muted, border),
                _buildDetailRow('Call Sign', activeVessel['callsign'], text, muted, border),
                _buildDetailRow('Vessel Type', activeVessel['type'], text, muted, border),
                _buildDetailRow(
                  'Dimensions (LOA x Beam)',
                  '${activeVessel['length'] ?? '—'}m x ${activeVessel['width'] ?? '—'}m',
                  text,
                  muted,
                  border,
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
        color: _kOrange,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.0,
                  vertical: 12.0,
                ),
                child: Column(
                  children: [
                    // Status bar
                    connectionWidget,
                    const SizedBox(height: 12),

                    // Search and Suggestions
                    searchWidget,
                    suggestionBox,
                    const SizedBox(height: 14),

                    // Detail View OR Main List
                    if (isMmsi) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _search = '';
                              _searchController.text = '';
                            });
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 15),
                          label: const Text('Back to Vessel Ledger'),
                          style: TextButton.styleFrom(
                            foregroundColor: _kBrown,
                            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Map Container
                      Container(
                        height: 320,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: border, width: 1.0),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: IframeWidget(
                          mmsi: _search,
                          vesselName: activeVessel?['name']?.toString(),
                          destination: activeVessel?['destination']?.toString(),
                          speed: activeVessel?['speed']?.toString(),
                          lat: (activeVessel?['lat'] as num?)?.toDouble(),
                          lon: (activeVessel?['lon'] as num?)?.toDouble(),
                        ),
                      ),
                      const SizedBox(height: 14),

                      buildVoyageDetails(),
                    ] else ...[
                      if (_loading)
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 6,
                          separatorBuilder: (ctx, i) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, i) => const ShimmerListTile(),
                        )
                      else if (filtered.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 40,
                            horizontal: 20,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: border, width: 1.0),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.directions_boat_outlined, size: 40, color: muted),
                              const SizedBox(height: 12),
                              Text(
                                'No Vessels In Range',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _search.isNotEmpty
                                    ? 'Try modifying your search keywords.'
                                    : 'Waiting for live AIS telemetry in Ghana territorial waters...',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: muted),
                              ),
                            ],
                          ),
                        )
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
                            final speedColor = isUnderway ? _kGreen : _kAmber;
                            final speedText = isUnderway
                                ? '${v['speed']} kn'
                                : 'At Anchor';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: border, width: 1.0),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: surfaceRaised,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: border, width: 1.0),
                                        ),
                                        child: Icon(
                                          v['mmsi'] != null
                                              ? Icons.directions_boat_rounded
                                              : Icons.local_shipping_rounded,
                                          color: _kBrown,
                                          size: 19,
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
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                color: text,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              v['mmsi'] != null
                                                  ? 'MMSI: ${v['mmsi']} · ${v['type'] ?? ''}'
                                                  : 'Container: ${v['container'] ?? 'N/A'}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: muted,
                                                fontFeatures: const [FontFeature.tabularFigures()],
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
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: speedColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: speedColor.withValues(alpha: 0.3),
                                                width: 1.0,
                                              ),
                                            ),
                                            child: Text(
                                              speedText,
                                              style: TextStyle(
                                                color: speedColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          ),
                                          if (v['last_update'] != null) ...[
                                            const SizedBox(height: 4),
                                            _buildUpdateTime(v['last_update'], muted),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _buildVoyageInfo(v, surfaceRaised, border, text, muted),
                                  const SizedBox(height: 10),
                                  _buildBottomActions(v, text, muted),
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

  Widget _buildUpdateTime(dynamic lastUpdate, Color muted) {
    final localTime = DateTime.tryParse(lastUpdate.toString())?.toLocal();
    if (localTime == null) return const SizedBox.shrink();
    final timeStr =
        "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:${localTime.second.toString().padLeft(2, '0')}";
    return Text(
      timeStr,
      style: TextStyle(
        fontSize: 11,
        color: muted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _buildVoyageInfo(
    dynamic v,
    Color surfaceRaised,
    Color border,
    Color text,
    Color muted,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 1.0),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Destination',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  v['destination']?.toString() ?? 'N/A',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: text,
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
                  style: TextStyle(
                    fontSize: 10.5,
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  v['eta']?.toString() ?? 'N/A',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: text,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

  Widget _buildBottomActions(dynamic v, Color text, Color muted) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.location_on_outlined, size: 13, color: muted),
            const SizedBox(width: 4),
            Text(
              'Pos: ${v['lat'] != null ? double.tryParse(v['lat'].toString())?.toStringAsFixed(4) : '0.0000'}, ${v['lng'] != null ? double.tryParse(v['lng'].toString())?.toStringAsFixed(4) : '0.0000'}',
              style: TextStyle(
                fontSize: 11.5,
                color: muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Track Vessel',
            style: TextStyle(
              color: _kBrown,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
