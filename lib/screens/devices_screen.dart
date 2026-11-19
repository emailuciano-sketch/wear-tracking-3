import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/traccar_service.dart';
import '../utils/formatters.dart';

class DeviceSelectionResult {
  final int? deviceId;
  final bool clearFocus;

  const DeviceSelectionResult({this.deviceId, this.clearFocus = false});
}

class DevicesScreen extends StatefulWidget {
  final int selectedDeviceId;

  const DevicesScreen({super.key, this.selectedDeviceId = 0});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isLoading = true;
  String? _error;
  String _query = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadData(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    final service = TraccarService.instance;
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      await service.getDevices();
      await service.getLastPositions();
      if (mounted) {
        _error = null;
      }
    } catch (e) {
      if (mounted && service.devices.isEmpty) {
        _error = e.toString();
      }
    } finally {
      if (mounted) {
        setState(() {
          if (!silent) _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = TraccarService.instance;
    final allDevices = service.devices.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final filtered = _query.isEmpty
        ? allDevices
        : allDevices
            .where((d) => d.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF007AA5),
        foregroundColor: Colors.white,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Cerca dispositivo...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              )
            : const Text('Devices'),
        actions: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop(
                    const DeviceSelectionResult(clearFocus: true),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x26FFFFFF),
                    border: Border.all(color: Colors.white),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'MOSTRA TUTTI',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _query = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: _isLoading && allDevices.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _error != null
                              ? 'Errore caricamento dispositivi: $_error'
                              : 'Nessun dispositivo trovato',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => _loadData(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007AA5),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Riprova'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final device = filtered[index];
                final pos = service.positions[device.id];
                final suffix = markerSuffixFor(device, pos);
                final isSelected = widget.selectedDeviceId != 0 &&
                    device.id == widget.selectedDeviceId;
                final statusText = buildDeviceStatusLabel(device, pos);

                return InkWell(
                  onTap: () {
                    Navigator.of(context).pop(
                      DeviceSelectionResult(deviceId: device.id),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Row(
                      children: <Widget>[
                        _AssetMarkerThumb(
                          category: device.category,
                          suffix: suffix,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                device.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? const Color(0xFF00A82D)
                                      : Colors.black,
                                ),
                              ),
                              Text(
                                statusText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _AssetMarkerThumb extends StatelessWidget {
  final String category;
  final String suffix;

  const _AssetMarkerThumb({required this.category, required this.suffix});

  @override
  Widget build(BuildContext context) {
    final path = 'assets/markers/marker_${category}_$suffix.png';
    final fallback = 'assets/markers/marker_default_$suffix.png';
    return Image.asset(
      path,
      width: 36,
      height: 36,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Image.asset(
        fallback,
        width: 36,
        height: 36,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(
          Icons.navigation,
          size: 32,
          color: Color(0xFF007AA5),
        ),
      ),
    );
  }
}
