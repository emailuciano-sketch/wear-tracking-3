import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/traccar_models.dart';
import '../services/traccar_service.dart';
import '../utils/formatters.dart';

class DeviceInfoScreen extends StatefulWidget {
  final int deviceId;

  const DeviceInfoScreen({super.key, required this.deviceId});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  TraccarDevice? _device;
  TraccarPosition? _position;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    final service = TraccarService.instance;
    _device = service.devices[widget.deviceId];
    _position = service.positions[widget.deviceId];
    _fetchInfo();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchInfo(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchInfo() async {
    final service = TraccarService.instance;
    try {
      await service.getDevices();
      final dev = service.devices[widget.deviceId];
      if (dev != null && dev.positionId > 0) {
        final posList =
            await service.getPositionsById(dev.id, dev.positionId);
        if (posList.isNotEmpty) {
          service.positions[dev.id] = posList.first;
        }
      } else {
        await service.getLastPositions();
      }
      if (mounted) {
        setState(() {
          _device = service.devices[widget.deviceId];
          _position = service.positions[widget.deviceId];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatAttributeValue(String key, dynamic val) {
    if (key == 'totalDistance' || key == 'distance') {
      final numVal = (val as num?)?.toDouble() ?? 0.0;
      return '${(numVal / 1000.0).toStringAsFixed(2)} km';
    }
    if (key == 'hours') {
      final numVal = (val as num?)?.toInt() ?? 0;
      return '${numVal ~/ 3600000} hr';
    }
    return val.toString();
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    final position = _position;
    final attrs = position?.attributes ?? const <String, dynamic>{};
    final gsmSignal = formatGsmSignal(position);
    const hiddenSignalKeys = <String>{'rssi', 'gsm', 'gsmSignal', 'signal'};
    final statusRows = <Widget>[];
    var insertedUnderSat = false;
    for (final entry in attrs.entries) {
      if (gsmSignal != null && hiddenSignalKeys.contains(entry.key)) {
        continue;
      }
      statusRows.add(
        _KeyValueRow(
          label: capitalizeWord(entry.key),
          value: _formatAttributeValue(entry.key, entry.value),
        ),
      );
      if (entry.key == 'sat') {
        statusRows.add(
          _KeyValueRow(
            label: 'GSM Signal',
            value: gsmSignal ?? 'N/D',
          ),
        );
        insertedUnderSat = true;
      }
    }
    if (!insertedUnderSat && gsmSignal != null) {
      statusRows.add(
        _KeyValueRow(
          label: 'GSM Signal',
          value: gsmSignal,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF007AA5),
        foregroundColor: Colors.white,
        title: const Text('Device Info'),
      ),
      body: _isLoading && device == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(10),
              children: <Widget>[
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Text(
                      device?.name ?? 'Name',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Location',
                          style: TextStyle(fontSize: 20, color: Colors.black),
                        ),
                        const SizedBox(height: 12),
                        _KeyValueRow(
                          label: 'Latitude',
                          value: position != null
                              ? position.latitude.toStringAsFixed(5)
                              : 'Loading...',
                        ),
                        _KeyValueRow(
                          label: 'Longitude',
                          value: position != null
                              ? position.longitude.toStringAsFixed(5)
                              : 'Loading...',
                        ),
                        _KeyValueRow(
                          label: 'Last Update',
                          value: formatDateTime(
                            device?.lastUpdate ?? position?.fixTime,
                          ),
                        ),
                        _KeyValueRow(
                          label: 'Direction',
                          value: position != null
                              ? compassDirection(position.course)
                              : 'Loading...',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'Status',
                          style: TextStyle(fontSize: 20, color: Colors.black),
                        ),
                        const SizedBox(height: 12),
                        if (statusRows.isEmpty)
                          const Text(
                            'No Data',
                            style: TextStyle(color: Colors.black54),
                          )
                        else
                          ...statusRows,
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _KeyValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 125,
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
          ),
          const Text(':  ', style: TextStyle(fontSize: 15)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
