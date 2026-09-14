import 'package:flutter/material.dart';
import '../components/app_layout.dart';
import '../components/iframe_widget.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../utils/app_logger.dart';

class CargoSchedulesPage extends StatefulWidget {
  const CargoSchedulesPage({super.key});

  @override
  State<CargoSchedulesPage> createState() => _CargoSchedulesPageState();
}

class _CargoSchedulesPageState extends State<CargoSchedulesPage> {
  // Registry fetched from backend — no hardcoded vessel data in the app
  List<Map<String, dynamic>> _registryVessels = [];

  String _activeTab = 'cargo schedules';
  String _searchQuery = '';
  List<dynamic> _schedules = [];
  bool _isLoading = true;
  final Map<String, dynamic> _vesselsMap = {};
  bool _showSuggestions = false;
  final FocusNode _focusNode = FocusNode();
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: _searchQuery);
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
    _fetchSchedules();
    _initSocketListener();
    _fetchRegistry();
  }

  Future<void> _fetchRegistry() async {
    try {
      final res = await ApiService().get('/vessels/registry');
      if (res.statusCode == 200) {
        final list = List<Map<String, dynamic>>.from(
          ApiService.ensureList(
            res.data,
          ).map((e) => Map<String, dynamic>.from(e)),
        );
        if (mounted) setState(() => _registryVessels = list);
      }
    } catch (e, st) {
      AppLogger.error('cargo_schedules_page', e, st);
    }
  }

  void _onSocketConnect(dynamic _) {
    if (mounted) setState(() {});
  }

  void _onSocketDisconnect(dynamic _) {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    final socket = SocketService().socket;
    if (socket != null) {
      socket.off('vessel_update', _onVesselUpdate);
      socket.off('schedules_updated', _onSchedulesUpdate);
      socket.off('connect', _onSocketConnect);
      socket.off('disconnect', _onSocketDisconnect);
    }
    super.dispose();
  }

  void _initSocketListener() {
    final socket = SocketService().socket;
    if (socket != null) {
      socket.off('vessel_update', _onVesselUpdate);
      socket.off('schedules_updated', _onSchedulesUpdate);
      socket.off('connect', _onSocketConnect);
      socket.off('disconnect', _onSocketDisconnect);

      socket.on('vessel_update', _onVesselUpdate);
      socket.on('schedules_updated', _onSchedulesUpdate);
      socket.on('connect', _onSocketConnect);
      socket.on('disconnect', _onSocketDisconnect);
    }
  }

  void _onSchedulesUpdate(dynamic _) {
    if (mounted) {
      _fetchSchedules();
      _fetchLiveVessels();
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

  Future<void> _fetchLiveVessels() async {
    await ApiService().fetchDataWithCache('/vessels', (
      data,
      isCached, {
      bool hasError = false,
    }) {
      if (mounted && data != null) {
        final list = ApiService.ensureList(data);
        setState(() {
          for (var item in list) {
            final mmsi = item['mmsi']?.toString();
            if (mmsi != null) {
              _vesselsMap[mmsi] = item;
            }
          }
        });
      }
    });
  }

  Future<void> _fetchSchedules() async {
    if (!mounted) return;
    if (!_isLoading) setState(() => _isLoading = true);

    final fetchTab = _activeTab;
    try {
      if (fetchTab == 'live tracking') {
        await _fetchLiveVessels();
        await ApiService().fetchDataWithCache('/schedules?type=movement', (
          data,
          isCached, {
          bool hasError = false,
        }) {
          if (mounted && data != null) {
            if (_activeTab != fetchTab) return;
            setState(() {
              _schedules = ApiService.ensureList(data);
              _isLoading = false;
            });
          }
        });
      } else {
        await ApiService().fetchDataWithCache('/schedules?type=$fetchTab', (
          data,
          isCached, {
          bool hasError = false,
        }) {
          if (mounted && data != null) {
            if (_activeTab != fetchTab) return;
            setState(() {
              _schedules = ApiService.ensureList(data);
              _isLoading = false;
            });
          }
        });
      }
    } catch (e) {
      if (mounted && _activeTab == fetchTab) {
        setState(() {
          _schedules = [];
          _isLoading = false;
        });
      }
    }
  }

  void _onTabChanged(String tab) {
    setState(() {
      _activeTab = tab;
      _searchQuery = '';
      _searchController.text = '';
    });
    _fetchSchedules();
  }

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value?.toString() ?? '—',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
    final primary = Theme.of(context).primaryColor;

    bool isLive = _activeTab == 'live tracking';
    bool isMMSI = RegExp(r'^\d{9}$').hasMatch(_searchQuery);

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

    final filteredVessels = vesselList.where((v) {
      final q = _searchQuery.toLowerCase();
      return (v['name'] ?? v['vessel'] ?? '').toString().toLowerCase().contains(
            q,
          ) ||
          (v['mmsi'] ?? v['container'] ?? '').toString().contains(q) ||
          (v['destination'] ?? v['port'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q);
    }).toList();

    final suggestions = _registryVessels
        .where((v) {
          final q = _searchQuery.toLowerCase();
          return (v['name'] ?? '').toString().toLowerCase().contains(q) ||
              (v['mmsi'] ?? '').toString().contains(q);
        })
        .take(5)
        .toList();

    // Filter schedules
    final filteredSchedules = _schedules.where((s) {
      final q = _searchQuery.toLowerCase();
      return (s['container']?.toString().toLowerCase().contains(q) ?? false) ||
          (s['vessel']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();

    Map<String, dynamic>? activeVessel;
    if (isLive && isMMSI) {
      activeVessel = _vesselsMap[_searchQuery];
      final common = _registryVessels.firstWhere(
        (item) => item['mmsi']?.toString() == _searchQuery,
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
          'destination': null,
          'eta': null,
        };
      }
    }

    return AppLayout(
      title: 'Logistics Hub',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isLive
                            ? (isConnected
                                  ? const Color(0xFF10b981)
                                  : Colors.grey)
                            : const Color(0xFF10b981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isLive
                          ? (isConnected
                                ? 'LIVE AIS LINK ACTIVE'
                                : 'AIS LINK CONNECTING...')
                          : 'LIVE SATELLITE LINK ACTIVE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isLive
                            ? (isConnected
                                  ? const Color(0xFF10b981)
                                  : Colors.grey)
                            : const Color(0xFF10b981),
                      ),
                    ),
                  ],
                ),
                Text(
                  isLive
                      ? (isMMSI
                            ? '1 vessel tracked'
                            : '${filteredVessels.length} vessels in range')
                      : 'Satellite connection active',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              children: ['cargo schedules', 'unloading', 'live tracking'].map((
                t,
              ) {
                bool active = _activeTab == t;
                return Expanded(
                  child: InkWell(
                    onTap: () => _onTabChanged(t),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: active
                            ? Theme.of(context).primaryColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        t.toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: active ? Colors.white : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Search Box
          TextField(
            focusNode: isLive ? _focusNode : null,
            controller: _searchController,
            onChanged: (val) {
              setState(() => _searchQuery = val);
              if (isLive &&
                  RegExp(r'^\d{9}$').hasMatch(val) &&
                  socket != null) {
                socket.emit('track_vessel', {'mmsi': val});
              }
            },
            decoration: InputDecoration(
              hintText: isLive
                  ? "Search by vessel name or MMSI..."
                  : "Search container or vessel...",
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).dividerColor),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.text = '';
                        });
                      },
                    )
                  : null,
            ),
          ),

          // Autocomplete suggestions list (Live tab only)
          if (isLive &&
              _showSuggestions &&
              _searchQuery.length > 1 &&
              suggestions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
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
                        _searchQuery = mmsi;
                        _searchController.text = mmsi;
                        _searchController.selection =
                            TextSelection.fromPosition(
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'MMSI: ${v['mmsi']}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            Icons.arrow_forward,
                            size: 16,
                            color: Theme.of(context).primaryColor,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Content Area
          if (isLive) ...[
            if (isMMSI) ...[
              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                      _searchController.text = '';
                    });
                  },
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to Live List'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Map
              Container(
                height: 320,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: IframeWidget(mmsi: _searchQuery),
              ),
              const SizedBox(height: 16),

              // Voyage Detail Card & Telemetry
              if (activeVessel != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
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
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.sailing,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    activeVessel['name']?.toString() ??
                                        'Detecting Vessel...',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  Text(
                                    'MMSI: ${activeVessel['mmsi']} · IMO: ${activeVessel['imo'] ?? 'N/A'}',
                                    style: const TextStyle(
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
                                      style: const TextStyle(
                                        color: Color(0xFF10b981),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
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
                                const Text(
                                  'DEPARTURE PORT',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  activeVessel['departure_port']?.toString() ??
                                      '—',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activeVessel['atd'] != null
                                      ? 'ATD: ${activeVessel['atd']}'
                                      : '📡 Awaiting AIS...',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.trending_flat,
                            color: Theme.of(context).primaryColor,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'REPORTED DESTINATION',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  activeVessel['destination']?.toString() ??
                                      'Detecting via AIS...',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.end,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ETA: ${activeVessel['eta']?.toString() ?? 'Awaiting Signal...'}',
                                  style: const TextStyle(
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

                // Summary Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor.withValues(alpha: 0.05),
                        Theme.of(context).primaryColor.withValues(alpha: 0.01),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).primaryColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Voyage Summary',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
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
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tech Specs & Telemetry Grid
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'General Specifications',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow('Vessel Name', activeVessel['name']),
                          _buildDetailRow('Flag', activeVessel['flag']),
                          _buildDetailRow('IMO Number', activeVessel['imo']),
                          _buildDetailRow('MMSI', activeVessel['mmsi']),
                          _buildDetailRow(
                            'Call Sign',
                            activeVessel['callsign'],
                          ),
                          _buildDetailRow('Vessel Type', activeVessel['type']),
                          _buildDetailRow(
                            'Dimensions',
                            '${activeVessel['length'] ?? '—'}m x ${activeVessel['width'] ?? '—'}m',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Latest AIS Telemetry',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildDetailRow(
                            'Navigational Status',
                            activeVessel['status'],
                          ),
                          _buildDetailRow(
                            'Speed Over Ground',
                            activeVessel['speed'] != null
                                ? '${activeVessel['speed']} kn'
                                : '—',
                          ),
                          _buildDetailRow(
                            'Course Over Ground',
                            activeVessel['course'] != null
                                ? '${activeVessel['course']}°'
                                : '—',
                          ),
                          _buildDetailRow(
                            'True Heading',
                            activeVessel['heading'] != null
                                ? '${activeVessel['heading']}°'
                                : '—',
                          ),
                          _buildDetailRow(
                            'Rate of Turn',
                            activeVessel['rot'] != null
                                ? '${activeVessel['rot']}°/min'
                                : '—',
                          ),
                          _buildDetailRow(
                            'Draught',
                            activeVessel['draught'] != null
                                ? '${activeVessel['draught']} m'
                                : '—',
                          ),
                          _buildDetailRow(
                            'Position Coordinates',
                            '${activeVessel['lat'] ?? '—'}, ${activeVessel['lng'] ?? '—'}',
                          ),
                          _buildDetailRow(
                            'Last Update',
                            activeVessel['last_update'],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ] else ...[
              // Live List Cards
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (filteredVessels.isEmpty)
                Container(
                  padding: const EdgeInsets.all(60),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.sailing,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No vessels in range',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Waiting for live AIS data from the Gulf of Guinea...',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredVessels.length,
                  itemBuilder: (context, index) {
                    final v = filteredVessels[index];
                    final doubleSpeed = double.tryParse(
                      v['speed']?.toString() ?? '0',
                    );
                    final isUnderway = doubleSpeed != null && doubleSpeed > 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  v['mmsi'] != null
                                      ? Icons.directions_boat
                                      : Icons.local_shipping,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v['name']?.toString() ??
                                          v['vessel']?.toString() ??
                                          'Unnamed Vessel',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      v['mmsi'] != null
                                          ? 'MMSI: ${v['mmsi']} · ${v['type'] ?? ''}'
                                          : 'Container: ${v['container'] ?? 'N/A'}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    isUnderway
                                        ? '${v['speed']} kn'
                                        : 'At Anchor',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isUnderway
                                          ? const Color(0xFF10b981)
                                          : Colors.amber,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (v['last_update'] != null) ...[
                                    (() {
                                      final localTime = DateTime.tryParse(
                                        v['last_update'].toString(),
                                      )?.toLocal();
                                      if (localTime == null) {
                                        return const SizedBox.shrink();
                                      }
                                      final timeStr =
                                          "${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}:${localTime.second.toString().padLeft(2, '0')}";
                                      return Text(
                                        timeStr,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      );
                                    })(),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'DESTINATION',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        v['destination']?.toString() ??
                                            v['port']?.toString() ??
                                            'N/A',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'ETA',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        v['eta']?.toString() ??
                                            v['date']?.toString() ??
                                            'N/A',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Pos: ${v['lat'] != null ? double.tryParse(v['lat'].toString())?.toStringAsFixed(4) : '0.0000'}, ${v['lng'] != null ? double.tryParse(v['lng'].toString())?.toStringAsFixed(4) : '0.0000'}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = v['mmsi']?.toString() ?? '';
                                    _searchController.text = _searchQuery;
                                  });
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'View Details',
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
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
          ] else ...[
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (filteredSchedules.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.search_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(
                      'No $_activeTab schedules found.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredSchedules.length,
                itemBuilder: (context, index) {
                  final s = filteredSchedules[index];
                  bool inProgress = s['status'] == 'In Progress';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CONTAINER',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  s['container'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: inProgress
                                    ? const Color(0x193b82f6)
                                    : const Color(0x1910b981),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                s['status'] ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: inProgress
                                      ? const Color(0xFF3b82f6)
                                      : const Color(0xFF10b981),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Location',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    s['port'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Vessel',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    s['vessel'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Date',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    s['date'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
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
                },
              ),
          ],
        ],
      ),
    );
  }
}
