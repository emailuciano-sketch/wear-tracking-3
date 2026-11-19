import 'dart:async';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../models/traccar_models.dart';
import '../services/marker_icons.dart';
import '../services/traccar_service.dart';
import '../utils/formatters.dart';

class DrawTripScreen extends StatefulWidget {
  final int deviceId;
  final String deviceName;
  final String startIso;
  final String endIso;

  const DrawTripScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.startIso,
    required this.endIso,
  });

  @override
  State<DrawTripScreen> createState() => _DrawTripScreenState();
}

class _DrawTripScreenState extends State<DrawTripScreen> {
  GoogleMapController? _controller;
  List<RoutePoint> _route = <RoutePoint>[];
  List<LatLng> _polylinePoints = <LatLng>[];
  final Set<Marker> _staticMarkers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};

  BitmapDescriptor? _replayIcon;
  bool _satellite = false;
  bool _isLoading = true;
  bool _isPlaying = false;
  int _playIndex = 0;
  int _stepMs = 1000;
  Timer? _playTimer;

  @override
  void initState() {
    super.initState();
    _satellite = TraccarService.instance.satelliteView;
    _loadRouteAndEvents();
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

  List<LatLng> _deduplicatePoints(List<RoutePoint> route) {
    final out = <LatLng>[];
    for (var i = 0; i < route.length; i++) {
      final p = route[i];
      if (p.latitude == 0.0 && p.longitude == 0.0) continue;
      final ll = LatLng(p.latitude, p.longitude);
      if (out.isEmpty || i == route.length - 1) {
        out.add(ll);
      } else {
        final prev = out.last;
        if ((ll.latitude - prev.latitude).abs() > 0.00001 ||
            (ll.longitude - prev.longitude).abs() > 0.00001) {
          out.add(ll);
        }
      }
    }
    if (out.isEmpty && route.isNotEmpty) {
      out.add(LatLng(route.first.latitude, route.first.longitude));
    }
    return out;
  }

  void _rebuildPolylines() {
    if (_polylinePoints.isEmpty) {
      _polylines = <Polyline>{};
      return;
    }
    _polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId('trip_route'),
        points: _polylinePoints,
        color: _satellite
            ? const Color(0xFF00E5FF)
            : const Color(0xFF0055FF),
        width: 5,
      ),
    };
  }

  Future<void> _loadRouteAndEvents() async {
    final service = TraccarService.instance;
    try {
      final startIcon = await MarkerIconCache.instance.getImageAssetIcon(
        'assets/images/start.png',
        width: 80,
        height: 80,
      );
      final stopIcon = await MarkerIconCache.instance.getImageAssetIcon(
        'assets/images/stop.png',
        width: 80,
        height: 100,
      );
      final eventIcon = await MarkerIconCache.instance.getImageAssetIcon(
        'assets/images/event_marker.png',
        width: 72,
        height: 72,
      );
      _replayIcon = await MarkerIconCache.instance.getImageAssetIcon(
        'assets/images/navigation.png',
        width: 74,
        height: 74,
      );

      final routeFuture =
          service.getRoute(widget.deviceId, widget.startIso, widget.endIso);
      final stopsFuture = service
          .getStops(widget.deviceId, widget.startIso, widget.endIso)
          .catchError((_) => <StopReportModel>[]);

      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        routeFuture,
        stopsFuture,
      ]);
      final route = results[0] as List<RoutePoint>;
      final stops = results[1] as List<StopReportModel>;

      if (route.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Data')),
        );
        Navigator.of(context).pop();
        return;
      }

      final pts = _deduplicatePoints(route);

      _staticMarkers.clear();
      _staticMarkers.add(
        Marker(
          markerId: const MarkerId('trip_start'),
          position: pts.first,
          icon: startIcon,
          infoWindow: const InfoWindow(title: 'Start Point'),
        ),
      );
      _staticMarkers.add(
        Marker(
          markerId: const MarkerId('trip_end'),
          position: pts.last,
          icon: stopIcon,
          infoWindow: const InfoWindow(title: 'Stop Point'),
        ),
      );

      for (var i = 0; i < stops.length; i++) {
        final s = stops[i];
        if (s.latitude != 0 && s.longitude != 0) {
          _staticMarkers.add(
            Marker(
              markerId: MarkerId('stop_$i'),
              position: LatLng(s.latitude, s.longitude),
              icon: stopIcon,
              infoWindow: InfoWindow(
                title: 'Vehicle Stopped (${formatDurationMs(s.duration)})',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _route = route;
        _polylinePoints = pts;
        _rebuildPolylines();
        _isLoading = false;
        _isPlaying = true;
      });
      _fitRouteBounds(pts);
      _startPlaybackTimer();
      unawaited(_loadOptionalEvents(eventIcon));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore caricamento percorso: $e')),
      );
    }
  }

  Future<void> _loadOptionalEvents(BitmapDescriptor eventIcon) async {
    final service = TraccarService.instance;
    try {
      final events = await service
          .getEvents(widget.deviceId, widget.startIso, widget.endIso)
          .catchError((_) => <DeviceEventModel>[]);
      if (!mounted || events.isEmpty) return;

      var added = false;
      for (var i = 0; i < events.length && i < 50; i++) {
        final ev = events[i];
        if (ev.positionId <= 0) continue;
        try {
          final posList =
              await service.getPositionsById(ev.deviceId, ev.positionId);
          if (!mounted) return;
          if (posList.isNotEmpty) {
            final p = posList.first;
            _staticMarkers.add(
              Marker(
                markerId: MarkerId('event_${ev.id}_$i'),
                position: LatLng(p.latitude, p.longitude),
                icon: eventIcon,
                infoWindow: InfoWindow(
                  title: ev.type,
                  snippet: formatDateTime(p.fixTime),
                ),
              ),
            );
            added = true;
          }
        } catch (_) {}
      }
      if (added && mounted) {
        setState(() {});
      }
    } catch (_) {
      // /api/reports/events is optional (e.g. Traccar 4.14 returns HTTP 400 without extra params).
    }
  }

  Future<void> _fitRouteBounds(List<LatLng> pts) async {
    final c = _controller;
    if (c == null || pts.isEmpty) return;
    var minLat = pts.first.latitude;
    var maxLat = pts.first.latitude;
    var minLng = pts.first.longitude;
    var maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final center = LatLng((minLat + maxLat) / 2.0, (minLng + maxLng) / 2.0);
    if (pts.length == 1 ||
        ((maxLat - minLat) < 0.0005 && (maxLng - minLng) < 0.0005)) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(center, 16.0));
      return;
    }
    try {
      await c.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          60,
        ),
      );
    } catch (_) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(center, 14.0));
    }
  }

  void _startPlaybackTimer() {
    _playTimer?.cancel();
    if (!_isPlaying || _route.isEmpty) return;
    _playTimer = Timer.periodic(Duration(milliseconds: _stepMs), (_) {
      if (!mounted || !_isPlaying) return;
      if (_playIndex < _route.length - 1) {
        setState(() => _playIndex++);
        final pt = _route[_playIndex];
        _controller?.animateCamera(
          CameraUpdate.newLatLng(LatLng(pt.latitude, pt.longitude)),
        );
      } else {
        setState(() => _isPlaying = false);
        _playTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentPt = _route.isNotEmpty ? _route[_playIndex] : null;
    final cachedPos = TraccarService.instance.positions[widget.deviceId];
    final user = TraccarService.instance.currentUser;
    final initialTarget = currentPt != null
        ? LatLng(currentPt.latitude, currentPt.longitude)
        : (cachedPos != null && cachedPos.latitude != 0)
            ? LatLng(cachedPos.latitude, cachedPos.longitude)
            : (user != null && user.latitude != 0)
                ? LatLng(user.latitude, user.longitude)
                : const LatLng(41.9028, 12.4964);

    final markers = Set<Marker>.from(_staticMarkers);
    if (currentPt != null && _replayIcon != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('replay_marker'),
          position: LatLng(currentPt.latitude, currentPt.longitude),
          rotation: currentPt.course,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: _replayIcon!,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF007AA5),
        foregroundColor: Colors.white,
        title: Text(widget.deviceName),
        actions: <Widget>[
          IconButton(
            tooltip: 'Satellite',
            icon: Icon(_satellite ? Icons.map : Icons.satellite_alt),
            onPressed: () {
              setState(() {
                _satellite = !_satellite;
                _rebuildPolylines();
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialTarget,
              zoom: 14,
            ),
            mapType: _satellite ? MapType.hybrid : MapType.normal,
            markers: markers,
            polylines: _polylines,
            zoomControlsEnabled: false,
            onMapCreated: (c) {
              _controller = c;
              if (_polylinePoints.isNotEmpty) {
                _fitRouteBounds(_polylinePoints);
              }
            },
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
          if (currentPt != null)
            Positioned(
              left: 10,
              right: 10,
              bottom: 12,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          IconButton(
                            icon: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: const Color(0xFF007AA5),
                            ),
                            onPressed: () {
                              setState(() {
                                if (_isPlaying) {
                                  _isPlaying = false;
                                  _playTimer?.cancel();
                                } else {
                                  if (_playIndex >= _route.length - 1) {
                                    _playIndex = 0;
                                  }
                                  _isPlaying = true;
                                  _startPlaybackTimer();
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: (_route.length - 1).toDouble().clamp(1, 999999),
                              value: _playIndex.toDouble(),
                              onChanged: (val) {
                                final idx = val.round().clamp(0, _route.length - 1);
                                setState(() => _playIndex = idx);
                                final pt = _route[idx];
                                _controller?.moveCamera(
                                  CameraUpdate.newLatLng(
                                    LatLng(pt.latitude, pt.longitude),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            'Speed: ${knotsToKmh(currentPt.speed).toStringAsFixed(1)} km/h',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            formatDateTime(currentPt.fixTime),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: <Widget>[
                          const Text(
                            'Velocità riproduzione:',
                            style: TextStyle(fontSize: 12),
                          ),
                          Expanded(
                            child: Slider(
                              min: 100,
                              max: 1000,
                              divisions: 9,
                              value: (1100 - _stepMs).toDouble().clamp(100, 1000),
                              onChanged: (val) {
                                setState(() {
                                  _stepMs = (1100 - val.round()).clamp(100, 1000);
                                });
                                if (_isPlaying) _startPlaybackTimer();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
