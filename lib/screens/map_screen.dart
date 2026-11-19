import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/traccar_models.dart';
import '../services/marker_icons.dart';
import '../services/traccar_service.dart';
import '../utils/formatters.dart';
import '../utils/fullscreen_helper.dart';
import '../utils/map_links.dart';
import 'about_screen.dart';
import 'device_info_screen.dart';
import 'devices_screen.dart';
import 'login_screen.dart';
import 'report_configure_dialog.dart';
import 'settings_screen.dart';

class _MarkerTweenState {
  LatLng startPos;
  LatLng endPos;
  LatLng currentPos;
  double startRot;
  double endRot;
  double currentRot;
  int startMs;
  bool animating;
  BitmapDescriptor icon;

  _MarkerTweenState({
    required this.currentPos,
    required this.currentRot,
    required this.icon,
  })  : startPos = currentPos,
        endPos = currentPos,
        startRot = currentRot,
        endRot = currentRot,
        startMs = 0,
        animating = false;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  GoogleMapController? _mapController;
  final TraccarService _service = TraccarService.instance;

  final Map<int, _MarkerTweenState> _markerStates = <int, _MarkerTweenState>{};
  late final Ticker _ticker;
  Timer? _uiTickTimer;
  Timer? _myLocTimer;
  StreamSubscription<void>? _liveSub;

  int _selectedDeviceId = 0;
  bool _track = false;
  bool _showBottomSheet = false;
  bool _isMenuOpen = false;
  bool _hasFittedInitialBounds = false;
  bool _locationPermissionGranted = false;
  double _currentZoom = 14.0;
  int _pauseAutoFollowUntilMs = 0;
  Position? _myLocation;
  Orientation? _lastOrientation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    _ticker = createTicker(_onAnimTick);

    _liveSub = _service.onLiveUpdate.listen((_) => _syncMarkersFromService());
    _service.startRealtimeSync();
    if (_service.positions.isNotEmpty) {
      _syncMarkersFromService();
    }
    _initLocationPermissionAndFetch();

    _uiTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_selectedDeviceId != 0 &&
          _showBottomSheet &&
          _service.positions.containsKey(_selectedDeviceId)) {
        setState(() {});
      }
    });

    _myLocTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_locationPermissionGranted) {
        _refreshLocalPosition();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _lastOrientation = orientation;
      FullscreenHelper.apply(orientation);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        FullscreenHelper.apply(MediaQuery.of(context).orientation);
      }
      _service.startRealtimeSync();
      _service.fetchLatestPositions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _uiTickTimer?.cancel();
    _myLocTimer?.cancel();
    _liveSub?.cancel();
    _service.stopRealtimeSync();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initLocationPermissionAndFetch() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final granted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      if (mounted && granted != _locationPermissionGranted) {
        setState(() => _locationPermissionGranted = granted);
      }
      if (granted) {
        await _refreshLocalPosition();
      }
    } catch (_) {}
  }

  Future<void> _refreshLocalPosition() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        _myLocation = last;
      }
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (mounted) {
        _myLocation = current;
      }
    } catch (_) {}
  }

  double _resolveCourse(
    TraccarPosition? position,
    double? previousRotation,
  ) {
    final course = position?.course ?? 0.0;
    final speedKmh = position != null ? knotsToKmh(position.speed) : 0.0;
    if (previousRotation != null && speedKmh < 3.0 && course.abs() < 0.01) {
      return previousRotation;
    }
    return course;
  }

  Future<void> _syncMarkersFromService() async {
    if (!mounted) return;
    final positions = Map<int, TraccarPosition>.from(_service.positions);
    final devices = Map<int, TraccarDevice>.from(_service.devices);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var needsTicker = false;

    for (final entry in positions.entries) {
      final deviceId = entry.key;
      final pos = entry.value;
      final device = devices[deviceId];
      if (device == null || (pos.latitude == 0.0 && pos.longitude == 0.0)) {
        continue;
      }

      final suffix = markerSuffixFor(device, pos);
      final icon = await MarkerIconCache.instance.getMarkerIcon(
        category: device.category,
        suffix: suffix,
      );
      if (!mounted) return;

      final location = LatLng(pos.latitude, pos.longitude);
      final existing = _markerStates[deviceId];
      final course = _resolveCourse(pos, existing?.currentRot);

      if (existing == null) {
        _markerStates[deviceId] = _MarkerTweenState(
          currentPos: location,
          currentRot: course,
          icon: icon,
        );
        if (_track &&
            _selectedDeviceId == deviceId &&
            nowMs >= _pauseAutoFollowUntilMs) {
          _moveCameraToDevice(deviceId);
        }
      } else {
        existing.icon = icon;
        final moved =
            (existing.endPos.latitude - location.latitude).abs() > 1e-6 ||
                (existing.endPos.longitude - location.longitude).abs() > 1e-6 ||
                (existing.endRot - course).abs() > 0.5;
        if (moved) {
          existing.startPos = existing.currentPos;
          existing.endPos = location;
          existing.startRot = existing.currentRot;
          existing.endRot = course;
          existing.startMs = nowMs;
          existing.animating = true;
          needsTicker = true;
        } else if (!existing.animating &&
            _track &&
            _selectedDeviceId == deviceId &&
            nowMs >= _pauseAutoFollowUntilMs) {
          _moveCameraToDevice(deviceId);
        }
      }
    }

    if (needsTicker && !_ticker.isActive) {
      _ticker.start();
    }

    if (!_hasFittedInitialBounds &&
        _selectedDeviceId == 0 &&
        _markerStates.isNotEmpty &&
        _mapController != null) {
      _hasFittedInitialBounds = true;
      _fitAllMarkersCamera();
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _onAnimTick(Duration _) {
    if (!mounted) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var anyActive = false;

    for (final entry in _markerStates.entries) {
      final deviceId = entry.key;
      final state = entry.value;
      if (!state.animating) continue;

      final elapsed = nowMs - state.startMs;
      final t = (elapsed / 1000.0).clamp(0.0, 1.0);
      final newPos = _interpolateLatLng(t, state.startPos, state.endPos);
      final newRot = _computeRotation(t, state.startRot, state.endRot);

      state.currentPos = newPos;
      state.currentRot = newRot;
      if (t >= 1.0) {
        state.animating = false;
      } else {
        anyActive = true;
      }

      if (_track &&
          _selectedDeviceId == deviceId &&
          _mapController != null &&
          newPos.latitude.abs() > 1e-6 &&
          nowMs >= _pauseAutoFollowUntilMs) {
        _mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: newPos,
              zoom: _currentZoom,
              bearing: newRot,
            ),
          ),
        );
      }
    }

    if (!anyActive && _ticker.isActive) {
      _ticker.stop();
    }
    setState(() {});
  }

  LatLng _interpolateLatLng(double fraction, LatLng a, LatLng b) {
    final lat = (b.latitude - a.latitude) * fraction + a.latitude;
    var lngDelta = b.longitude - a.longitude;
    if (lngDelta.abs() > 180) {
      lngDelta -= lngDelta.sign * 360;
    }
    final lng = lngDelta * fraction + a.longitude;
    return LatLng(lat, lng);
  }

  double _computeRotation(double fraction, double start, double end) {
    final normalizeEnd = end - start;
    final normalizedEndAbs = (normalizeEnd + 360) % 360;
    final direction = normalizedEndAbs > 180 ? -1 : 1;
    final rotation =
        direction > 0 ? normalizedEndAbs : normalizedEndAbs - 360;
    return (fraction * rotation + start + 360) % 360;
  }

  Future<void> _moveCameraToDevice(
    int deviceId, {
    double? zoomOverride,
  }) async {
    final c = _mapController;
    final pos = _service.positions[deviceId];
    if (c == null || pos == null || pos.latitude == 0.0) return;

    final state = _markerStates[deviceId];
    final target = state?.currentPos ?? LatLng(pos.latitude, pos.longitude);
    final bearing = _resolveCourse(pos, state?.currentRot);
    final targetZoom = zoomOverride ?? _currentZoom;
    _currentZoom = targetZoom;

    await c.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: targetZoom,
          bearing: bearing,
        ),
      ),
    );
  }

  Future<void> _fitAllMarkersCamera() async {
    final c = _mapController;
    if (c == null || _markerStates.isEmpty) return;

    var minLat = double.infinity;
    var maxLat = -double.infinity;
    var minLng = double.infinity;
    var maxLng = -double.infinity;
    for (final s in _markerStates.values) {
      if (s.currentPos.latitude < minLat) minLat = s.currentPos.latitude;
      if (s.currentPos.latitude > maxLat) maxLat = s.currentPos.latitude;
      if (s.currentPos.longitude < minLng) minLng = s.currentPos.longitude;
      if (s.currentPos.longitude > maxLng) maxLng = s.currentPos.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2.0, (minLng + maxLng) / 2.0);
    if (_markerStates.length == 1 ||
        ((maxLat - minLat) < 0.0008 && (maxLng - minLng) < 0.0008)) {
      await c.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: center,
            zoom: 16.0,
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
      return;
    }

    try {
      await c.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          80,
        ),
      );
    } catch (_) {
      await c.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: center,
            zoom: 14.0,
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    }
  }

  Future<void> _resetMap() async {
    _service.fetchLatestPositions();
    if (_markerStates.isNotEmpty) {
      setState(() {
        _selectedDeviceId = 0;
        _track = false;
        _showBottomSheet = false;
      });
      await _fitAllMarkersCamera();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Showing all Devices')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device Not attached')),
      );
    }
  }

  Future<void> _centerOnMyLocation() async {
    await _initLocationPermissionAndFetch();
    if (!_locationPermissionGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permesso posizione necessario'),
          ),
        );
      }
      return;
    }
    final loc = _myLocation;
    if (loc != null && _mapController != null) {
      _pauseAutoFollowUntilMs = DateTime.now().millisecondsSinceEpoch + 10000;
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(loc.latitude, loc.longitude),
            zoom: 16,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Posizione GPS locale non ancora disponibile'),
        ),
      );
    }
  }

  Future<void> _openDevicesScreen() async {
    final result = await Navigator.of(context).push<DeviceSelectionResult>(
      MaterialPageRoute<DeviceSelectionResult>(
        builder: (_) => DevicesScreen(selectedDeviceId: _selectedDeviceId),
      ),
    );
    if (!mounted || result == null) return;

    if (result.clearFocus) {
      setState(() {
        _selectedDeviceId = 0;
        _track = false;
        _showBottomSheet = false;
      });
      await _fitAllMarkersCamera();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Showing all Devices')),
        );
      }
      return;
    }

    final targetId = result.deviceId;
    if (targetId != null && targetId != 0) {
      final sameDevice = targetId == _selectedDeviceId;
      setState(() {
        _selectedDeviceId = targetId;
        _track = true;
        _pauseAutoFollowUntilMs = 0;
        _showBottomSheet = true;
      });
      await _syncMarkersFromService();
      await _moveCameraToDevice(
        targetId,
        zoomOverride: sameDevice ? _currentZoom : 18.0,
      );
    }
  }

  Future<void> _openReport() async {
    if (_selectedDeviceId == 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select Device'),
          content: const Text('Please select any Device'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final devName = _service.devices[_selectedDeviceId]?.name ?? 'Device';
    await showReportConfigureDialog(
      context,
      deviceId: _selectedDeviceId,
      deviceName: devName,
    );
  }

  Future<void> _logout() async {
    await _service.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Set<Marker> _buildVisibleMarkers() {
    final set = <Marker>{};
    final showLabel = _service.markerLabel;
    for (final entry in _markerStates.entries) {
      final id = entry.key;
      if (_selectedDeviceId != 0 && id != _selectedDeviceId) {
        continue;
      }
      final state = entry.value;
      final device = _service.devices[id];
      if (device == null) continue;

      set.add(
        Marker(
          markerId: MarkerId('dev_$id'),
          position: state.currentPos,
          rotation: state.currentRot,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: state.icon,
          infoWindow: showLabel
              ? InfoWindow(title: device.name)
              : InfoWindow.noText,
          onTap: () {
            setState(() {
              _selectedDeviceId = id;
              _track = true;
              _pauseAutoFollowUntilMs = 0;
              _showBottomSheet = true;
            });
            _moveCameraToDevice(id, zoomOverride: _currentZoom);
          },
        ),
      );
    }
    return set;
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final topInset = math.max(viewPadding.top + 12.0, 20.0);
    final rightInset = math.max(padding.right + 12.0, 16.0);
    final selectedDevice = _selectedDeviceId != 0
        ? _service.devices[_selectedDeviceId]
        : null;
    final selectedPos = _selectedDeviceId != 0
        ? _service.positions[_selectedDeviceId]
        : null;

    final user = _service.currentUser;
    final initialTarget = (user != null && user.latitude != 0)
        ? LatLng(user.latitude, user.longitude)
        : const LatLng(41.9028, 12.4964);
    final initialZoom =
        (user != null && user.zoom > 0) ? user.zoom.toDouble() : 6.0;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerMove: (event) {
              if (_track && event.delta.distance > 3.0) {
                _pauseAutoFollowUntilMs =
                    DateTime.now().millisecondsSinceEpoch + 2500;
              }
            },
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: initialZoom,
              ),
              mapType:
                  _service.satelliteView ? MapType.hybrid : MapType.normal,
              minMaxZoomPreference: const MinMaxZoomPreference(null, 18),
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              myLocationEnabled: _locationPermissionGranted,
              myLocationButtonEnabled: false,
              markers: _buildVisibleMarkers(),
              onCameraMove: (pos) {
                _currentZoom = pos.zoom;
              },
              onTap: (_) {
                if (_isMenuOpen) {
                  setState(() => _isMenuOpen = false);
                } else if (_showBottomSheet) {
                  setState(() => _showBottomSheet = false);
                }
              },
              onMapCreated: (controller) {
                _mapController = controller;
                _syncMarkersFromService();
              },
            ),
          ),

          // Outside tap barrier for in-layout dropdown menu (keeps immersive fullscreen intact in landscape)
          if (_isMenuOpen)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _isMenuOpen = false),
                child: const SizedBox.expand(),
              ),
            ),

          // 3 semi-transparent right-side control buttons
          Positioned(
            top: topInset,
            right: rightInset,
            child: Column(
              children: <Widget>[
                _SideTransparentButton(
                  icon: Icons.more_vert,
                  onTap: () {
                    setState(() => _isMenuOpen = !_isMenuOpen);
                  },
                ),
                const SizedBox(height: 8),
                _SideTransparentButton(
                  icon: Icons.my_location,
                  onTap: () {
                    if (_isMenuOpen) {
                      setState(() => _isMenuOpen = false);
                    }
                    _centerOnMyLocation();
                  },
                ),
                const SizedBox(height: 8),
                _SideTransparentButton(
                  icon: Icons.near_me,
                  onTap: () {
                    if (_isMenuOpen) {
                      setState(() => _isMenuOpen = false);
                    }
                    _openDevicesScreen();
                  },
                ),
              ],
            ),
          ),

          // In-layout dropdown menu anchored beside the 3 dots (order: Aggiorna, Storico, Settings, About, Logout)
          if (_isMenuOpen)
            Positioned(
              top: topInset,
              right: rightInset + 50,
              child: Material(
                elevation: 8,
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                child: IntrinsicWidth(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 170),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _DropdownMenuItem(
                            label: 'Aggiorna',
                            onTap: () {
                              setState(() => _isMenuOpen = false);
                              _resetMap();
                            },
                          ),
                          _DropdownMenuItem(
                            label: 'Storico',
                            onTap: () {
                              setState(() => _isMenuOpen = false);
                              _openReport();
                            },
                          ),
                          _DropdownMenuItem(
                            label: 'Settings',
                            onTap: () async {
                              setState(() => _isMenuOpen = false);
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                              if (mounted) setState(() {});
                            },
                          ),
                          _DropdownMenuItem(
                            label: 'About',
                            onTap: () {
                              setState(() => _isMenuOpen = false);
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const AboutScreen(),
                                ),
                              );
                            },
                          ),
                          _DropdownMenuItem(
                            label: 'Logout',
                            onTap: () {
                              setState(() => _isMenuOpen = false);
                              _logout();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Compact Device Info Bottom Panel
          if (_showBottomSheet && selectedDevice != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onVerticalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) > 150) {
                    setState(() => _showBottomSheet = false);
                  }
                },
                child: _DeviceBottomPanel(
                  device: selectedDevice,
                  position: selectedPos,
                  onStreetView: () {
                    if (selectedPos == null) return;
                    MapLinks.openStreetView(
                      context,
                      latitude: selectedPos.latitude,
                      longitude: selectedPos.longitude,
                    );
                  },
                  onDirections: () {
                    if (selectedPos == null) return;
                    MapLinks.openDirections(
                      context,
                      latitude: selectedPos.latitude,
                      longitude: selectedPos.longitude,
                    );
                  },
                  onDeviceInfo: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            DeviceInfoScreen(deviceId: selectedDevice.id),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SideTransparentButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SideTransparentButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x88000000),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x40FFFFFF), width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _DropdownMenuItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DropdownMenuItem({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF212121), fontSize: 15),
        ),
      ),
    );
  }
}

class _DeviceBottomPanel extends StatelessWidget {
  final TraccarDevice device;
  final TraccarPosition? position;
  final VoidCallback onStreetView;
  final VoidCallback onDirections;
  final VoidCallback onDeviceInfo;

  const _DeviceBottomPanel({
    required this.device,
    required this.position,
    required this.onStreetView,
    required this.onDirections,
    required this.onDeviceInfo,
  });

  @override
  Widget build(BuildContext context) {
    final pos = position;
    final moving = isDeviceMoving(device, pos);
    final statusColor = moving
        ? const Color(0xFF00A82D)
        : (device.status == 'online' || device.status == 'unknown')
            ? Colors.amber.shade700
            : Colors.redAccent;
    final statusText = buildDeviceStatusLabel(device, pos);

    return Material(
      color: Colors.white,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.navigation,
                    size: 18,
                    color: Color(0xFF007AA5),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  IconButton(
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 28),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    icon: const Icon(
                      Icons.streetview,
                      size: 20,
                      color: Color(0xFF007AA5),
                    ),
                    tooltip: 'Street View',
                    onPressed: onStreetView,
                  ),
                  IconButton(
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 28),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    icon: const Icon(
                      Icons.directions,
                      size: 20,
                      color: Color(0xFF007AA5),
                    ),
                    tooltip: 'Google Maps',
                    onPressed: onDirections,
                  ),
                  IconButton(
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 28),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    icon: const Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Color(0xFF007AA5),
                    ),
                    tooltip: 'Device Info',
                    onPressed: onDeviceInfo,
                  ),
                ],
              ),
              const Divider(height: 4, color: Color(0xFFD3D3D3)),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  Icon(Icons.circle, size: 13, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Last Update : ${formatDateTime(pos?.fixTime)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF808080),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
