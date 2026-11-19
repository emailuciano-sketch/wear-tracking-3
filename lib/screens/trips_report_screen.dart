import 'package:material_ui/material_ui.dart';

import '../models/traccar_models.dart';
import '../services/traccar_service.dart';
import '../utils/formatters.dart';
import 'draw_trip_screen.dart';

class TripsReportScreen extends StatefulWidget {
  final int deviceId;
  final String deviceName;
  final String startIso;
  final String endIso;

  const TripsReportScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.startIso,
    required this.endIso,
  });

  @override
  State<TripsReportScreen> createState() => _TripsReportScreenState();
}

class _TripsReportScreenState extends State<TripsReportScreen> {
  SummaryReport? _summary;
  List<TripReport> _trips = <TripReport>[];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    final service = TraccarService.instance;
    try {
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        service.getSummary(widget.deviceId, widget.startIso, widget.endIso),
        service.getTrips(widget.deviceId, widget.startIso, widget.endIso),
      ]);
      final summaries = results[0] as List<SummaryReport>;
      final trips = results[1] as List<TripReport>;
      if (mounted) {
        setState(() {
          _summary = summaries.isNotEmpty ? summaries.first : null;
          _trips = trips;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Errore caricamento storico: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final avgSpeed = summary != null
        ? '${knotsToKmh(summary.averageSpeed).toStringAsFixed(1)} km/h'
        : '--';
    final maxSpeed = summary != null
        ? '${knotsToKmh(summary.maxSpeed).toStringAsFixed(1)} km/h'
        : '--';
    final distKm = summary != null
        ? '${(summary.distance / 1000.0).toStringAsFixed(2)} km'
        : '--';
    final engineHr =
        summary != null ? formatDurationMs(summary.engineHours) : '--';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF007AA5),
        foregroundColor: Colors.white,
        title: const Text('Storico Viaggi'),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              summary?.deviceName.isNotEmpty == true
                                  ? summary!.deviceName
                                  : widget.deviceName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text('Avg Speed: $avgSpeed'),
                                ),
                                Expanded(
                                  child: Text('Max Speed: $maxSpeed'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text('Distance: $distKm'),
                                ),
                                Expanded(
                                  child: Text('Engine Hours: $engineHr'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF007AA5),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => DrawTripScreen(
                                      deviceId: widget.deviceId,
                                      deviceName: widget.deviceName,
                                      startIso: widget.startIso,
                                      endIso: widget.endIso,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('View Full Map'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _trips.isEmpty
                          ? const Center(
                              child: Text('Nessun viaggio trovato nel periodo'),
                            )
                          : ListView.separated(
                              itemCount: _trips.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final trip = _trips[index];
                                return ListTile(
                                  title: Text(
                                    '${formatDateTime(trip.startTime)} -> ${formatDateTime(trip.endTime)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'Distanza: ${(trip.distance / 1000.0).toStringAsFixed(2)} km • Durata: ${formatDurationMs(trip.duration)} • Max: ${knotsToKmh(trip.maxSpeed).toStringAsFixed(1)} km/h',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    if (trip.startTime == null ||
                                        trip.endTime == null) {
                                      return;
                                    }
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => DrawTripScreen(
                                          deviceId: widget.deviceId,
                                          deviceName: widget.deviceName,
                                          startIso:
                                              formatIsoUtc(trip.startTime!),
                                          endIso: formatIsoUtc(trip.endTime!),
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
