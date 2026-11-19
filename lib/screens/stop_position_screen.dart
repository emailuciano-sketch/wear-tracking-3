import 'package:material_ui/material_ui.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/traccar_models.dart';
import '../services/marker_icons.dart';
import '../services/traccar_service.dart';
import '../utils/formatters.dart';
import '../utils/map_links.dart';

class StopPositionScreen extends StatefulWidget {
  final int deviceId;
  final String deviceName;
  final int positionId;

  const StopPositionScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.positionId,
  });

  @override
  State<StopPositionScreen> createState() => _StopPositionScreenState();
}

class _StopPositionScreenState extends State<StopPositionScreen> {
  GoogleMapController? _controller;
  TraccarPosition? _position;
  Set<Marker> _markers = <Marker>{};
  bool _satellite = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _satellite = TraccarService.instance.satelliteView;
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final list = await TraccarService.instance.getPositionsById(
        widget.deviceId,
        widget.positionId,
      );
      if (list.isNotEmpty) {
        final pos = list.first;
        final icon = await MarkerIconCache.instance.getImageAssetIcon(
          'assets/images/event_marker.png',
          width: 80,
          height: 80,
        );
        final speedKmh = knotsToKmh(pos.speed).toStringAsFixed(1);

        if (!mounted) return;
        setState(() {
          _position = pos;
          _markers = <Marker>{
            Marker(
              markerId: const MarkerId('stop_pos'),
              position: LatLng(pos.latitude, pos.longitude),
              icon: icon,
              infoWindow: InfoWindow(
                title: widget.deviceName,
                snippet: 'Speed: $speedKmh km/h • ${formatDateTime(pos.fixTime)}',
              ),
            ),
          };
          _isLoading = false;
        });
        _controller?.moveCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
        );
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;
    final cachedPos = TraccarService.instance.positions[widget.deviceId];
    final user = TraccarService.instance.currentUser;
    final initialTarget = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : (cachedPos != null && cachedPos.latitude != 0)
            ? LatLng(cachedPos.latitude, cachedPos.longitude)
            : (user != null && user.latitude != 0)
                ? LatLng(user.latitude, user.longitude)
                : const LatLng(41.9028, 12.4964);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF007AA5),
        foregroundColor: Colors.white,
        title: const Text('Stop Position'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Satellite',
            icon: Icon(_satellite ? Icons.map : Icons.satellite_alt),
            onPressed: () => setState(() => _satellite = !_satellite),
          ),
          if (pos != null)
            IconButton(
              tooltip: 'Street View',
              icon: const Icon(Icons.streetview),
              onPressed: () {
                MapLinks.openStreetView(
                  context,
                  latitude: pos.latitude,
                  longitude: pos.longitude,
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialTarget,
              zoom: pos != null ? 15 : 12,
            ),
            mapType: _satellite ? MapType.hybrid : MapType.normal,
            markers: _markers,
            zoomControlsEnabled: false,
            onMapCreated: (c) {
              _controller = c;
              if (_position != null) {
                c.moveCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(_position!.latitude, _position!.longitude),
                    15,
                  ),
                );
              }
            },
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
          if (pos != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.deviceName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ultimo aggiornamento: ${formatDateTime(pos.fixTime)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
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
