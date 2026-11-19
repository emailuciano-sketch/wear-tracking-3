import 'package:material_ui/material_ui.dart';

import '../models/traccar_models.dart';
import '../services/traccar_service.dart';
import '../utils/formatters.dart';
import 'stop_position_screen.dart';

class StopsReportScreen extends StatefulWidget {
  final int deviceId;
  final String deviceName;
  final String startIso;
  final String endIso;

  const StopsReportScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.startIso,
    required this.endIso,
  });

  @override
  State<StopsReportScreen> createState() => _StopsReportScreenState();
}

class _StopsReportScreenState extends State<StopsReportScreen> {
  List<StopReportModel> _stops = <StopReportModel>[];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStops();
  }

  Future<void> _loadStops() async {
    try {
      final stops = await TraccarService.instance.getStops(
        widget.deviceId,
        widget.startIso,
        widget.endIso,
      );
      if (mounted) {
        setState(() {
          _stops = stops;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Errore caricamento fermate: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDurationMs = _stops.fold<int>(0, (sum, s) => sum + s.duration);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF007AA5),
        foregroundColor: Colors.white,
        title: const Text('Stop Report'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: <Widget>[
                    Card(
                      margin: const EdgeInsets.all(10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                _stops.isNotEmpty &&
                                        _stops.first.deviceName.isNotEmpty
                                    ? _stops.first.deviceName
                                    : widget.deviceName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              'Totale: ${formatDurationMs(totalDurationMs)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _stops.isEmpty
                          ? const Center(
                              child: Text('Nessuna fermata nel periodo'),
                            )
                          : ListView.separated(
                              itemCount: _stops.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final stop = _stops[index];
                                return ListTile(
                                  leading: const Icon(
                                    Icons.pause_circle_outline,
                                    color: Colors.redAccent,
                                  ),
                                  title: Text(
                                    '${formatDateTime(stop.startTime)} -> ${formatDateTime(stop.endTime)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Durata: ${formatDurationMs(stop.duration)}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => StopPositionScreen(
                                          deviceId: widget.deviceId,
                                          deviceName: stop.deviceName.isNotEmpty
                                              ? stop.deviceName
                                              : widget.deviceName,
                                          positionId: stop.positionId,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
