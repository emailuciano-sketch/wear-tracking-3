import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wear_tracking_flutter/models/traccar_models.dart';
import 'package:wear_tracking_flutter/screens/device_info_screen.dart';
import 'package:wear_tracking_flutter/screens/devices_screen.dart';
import 'package:wear_tracking_flutter/screens/login_screen.dart';
import 'package:wear_tracking_flutter/screens/settings_screen.dart';
import 'package:wear_tracking_flutter/services/traccar_service.dart';
import 'package:wear_tracking_flutter/utils/formatters.dart';
import 'package:wear_tracking_flutter/utils/marker_interpolation.dart';
import 'package:wear_tracking_flutter/utils/motion_state.dart';

void main() {
  test('compassDirection maps courses accurately', () {
    expect(compassDirection(0), 'N');
    expect(compassDirection(45), 'NE');
    expect(compassDirection(90), 'E');
    expect(compassDirection(135), 'SE');
    expect(compassDirection(180), 'S');
    expect(compassDirection(225), 'SW');
    expect(compassDirection(270), 'W');
    expect(compassDirection(315), 'NW');
  });

  test('formatGsmSignal decodes minifinder2 status, minifinder rssi, and osmand', () {
    final posMf2 = TraccarPosition.fromJson(<String, dynamic>{
      'id': 1,
      'deviceId': 4,
      'protocol': 'minifinder2',
      'latitude': 45.5,
      'longitude': 11.5,
      'attributes': <String, dynamic>{'status': 898826241, 'sat': 14},
    });
    expect(formatGsmSignal(posMf2), '58% (-77 dBm)');

    final posMf1 = TraccarPosition.fromJson(<String, dynamic>{
      'id': 2,
      'deviceId': 12,
      'protocol': 'minifinder',
      'latitude': 45.5,
      'longitude': 11.5,
      'attributes': <String, dynamic>{'rssi': 9, 'sat': 4},
    });
    expect(formatGsmSignal(posMf1), '29% (-95 dBm)');

    final posOsmand = TraccarPosition.fromJson(<String, dynamic>{
      'id': 3,
      'deviceId': 3,
      'protocol': 'osmand',
      'latitude': 45.5,
      'longitude': 11.5,
      'attributes': <String, dynamic>{'batteryLevel': 44.0},
    });
    expect(formatGsmSignal(posOsmand), isNull);
  });

  testWidgets('LoginScreen shows Wear-Tracking 4 without Server Settings and uses fixed server URL', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'url': 'https://custom.invalid.example',
    });
    await TraccarService.instance.init();

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Wear-Tracking 4'), findsOneWidget);
    expect(find.text('Server Settings'), findsNothing);
    expect(TraccarService.instance.serverUrl, 'https://pedinatore.com');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Change Password dialog opens and closes without assertion errors', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await TraccarService.instance.init();

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.tap(find.text('Change Password'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  test('interpolateLatLng preserves exact endpoints and handles antimeridian', () {
    const start = LatLng(45.4642, 9.1900);
    const end = LatLng(45.4742, 9.2100);
    expect(interpolateLatLng(0.0, start, end), start);
    expect(interpolateLatLng(1.0, start, end), end);

    final mid = interpolateLatLng(0.5, start, end);
    expect(mid.latitude, closeTo(45.4692, 1e-9));
    expect(mid.longitude, closeTo(9.2000, 1e-9));

    const antiA = LatLng(10.0, 179.9);
    const antiB = LatLng(10.0, -179.9);
    final antiMid = interpolateLatLng(0.5, antiA, antiB);
    expect(antiMid.longitude.abs(), closeTo(180.0, 1e-9));
  });

  test('interpolateRotation takes shortest angular path', () {
    expect(interpolateRotation(0.5, 350.0, 10.0), closeTo(0.0, 1e-9));
    expect(interpolateRotation(0.5, 10.0, 350.0), closeTo(0.0, 1e-9));
    expect(interpolateRotation(0.0, 350.0, 10.0), closeTo(350.0, 1e-9));
    expect(interpolateRotation(1.0, 350.0, 10.0), closeTo(10.0, 1e-9));
  });

  test('bearingDegrees computes cardinal headings accurately', () {
    const center = LatLng(45.5000, 11.5000);
    expect(bearingDegrees(center, const LatLng(45.5010, 11.5000)), closeTo(0.0, 0.2));
    expect(bearingDegrees(center, const LatLng(45.5000, 11.5010)), closeTo(90.0, 0.2));
    expect(bearingDegrees(center, const LatLng(45.4990, 11.5000)), closeTo(180.0, 0.2));
    expect(bearingDegrees(center, const LatLng(45.5000, 11.4990)), closeTo(270.0, 0.2));
  });

  test('shouldSnapToPosition snaps only jumps > 250 m', () {
    const origin = LatLng(45.4642, 9.1900);
    const shortHop = LatLng(45.4651, 9.1900); // ~100 m
    const longJump = LatLng(45.4669, 9.1900); // ~300 m
    expect(shouldSnapToPosition(origin, shortHop), isFalse);
    expect(shouldSnapToPosition(origin, longJump), isTrue);
  });

  group('Highway motion state & out-of-order protection', () {
    TraccarDevice makeDevice({String status = 'online', int id = 7}) {
      return TraccarDevice(
        id: id,
        positionId: 1,
        name: 'EV-201G',
        uniqueId: '862095056250316',
        category: 'car',
        status: status,
        lastUpdate: null,
        model: 'EV-201G',
        phone: null,
      );
    }

    TraccarPosition makePos({
      int id = 0,
      int deviceId = 7,
      required DateTime fixTime,
      required double lat,
      required double lon,
      double speedKnots = 0.0,
      double accuracy = 0.0,
      bool valid = true,
    }) {
      return TraccarPosition(
        id: id,
        deviceId: deviceId,
        fixTime: fixTime,
        outdated: false,
        valid: valid,
        latitude: lat,
        longitude: lon,
        altitude: 30.0,
        speed: speedKnots,
        course: 65.0,
        accuracy: accuracy,
        protocol: 'minifinder2',
        attributes: const <String, dynamic>{},
      );
    }

    test('real A4 highway burst (:40,:46,:44,:43,:39,:41) keeps :46 and recovers speed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = TraccarService.instance;
      await service.init();
      service.devices.clear();
      service.positions.clear();
      service.motionTracker.clear();

      final device = makeDevice(id: 7);
      service.devices[device.id] = device;
      final tEval = DateTime.utc(2026, 11, 21, 20, 8, 47);

      // Exact packet sequence & values from A4 highway log burst
      final burst = <TraccarPosition>[
        makePos(
          id: 40,
          fixTime: DateTime.utc(2026, 11, 21, 20, 8, 40),
          lat: 45.50555,
          lon: 11.46473,
          speedKnots: 64.8,
        ),
        makePos(
          id: 46,
          fixTime: DateTime.utc(2026, 11, 21, 20, 8, 46),
          lat: 45.50596,
          lon: 11.46638,
          speedKnots: 0.0,
        ),
        makePos(
          id: 44,
          fixTime: DateTime.utc(2026, 11, 21, 20, 8, 44),
          lat: 45.50585,
          lon: 11.46597,
          speedKnots: 65.3,
        ),
        makePos(
          id: 43,
          fixTime: DateTime.utc(2026, 11, 21, 20, 8, 43),
          lat: 45.50577,
          lon: 11.46556,
          speedKnots: 0.0,
        ),
        makePos(
          id: 39,
          fixTime: DateTime.utc(2026, 11, 21, 20, 8, 39),
          lat: 45.50545,
          lon: 11.46432,
          speedKnots: 64.8,
        ),
        makePos(
          id: 41,
          fixTime: DateTime.utc(2026, 11, 21, 20, 8, 41),
          lat: 45.50566,
          lon: 11.46515,
          speedKnots: 0.0,
        ),
      ];

      for (final p in burst) {
        service.ingestPosition(p, observedAt: tEval);
      }

      final current = service.positions[device.id]!;
      expect(current.fixTime, DateTime.utc(2026, 11, 21, 20, 8, 46));
      expect(
        shouldAcceptAsLatestPosition(
          current,
          makePos(
            id: 45,
            fixTime: DateTime.utc(2026, 11, 21, 20, 8, 45),
            lat: 45.50590,
            lon: 11.46610,
          ),
          currentObservedAt: tEval,
          now: tEval,
        ),
        isFalse,
      );

      final motion = service.motionFor(device.id, current, now: tEval);
      expect(motion.effectiveSpeedKmh, greaterThan(60.0));
      expect(motion.isSpeedFromDisplacement, isTrue);
      expect(
        markerSuffixFor(device, current, motion: motion, now: tEval),
        'online',
      );
      expect(
        buildDeviceStatusLabel(device, current, motion: motion, now: tEval),
        startsWith('Moving '),
      );
    });

    test('sustained >121 km/h driving with speed=0 stays online continuously past 30s', () {
      final tracker = DeviceMotionTracker();
      final device = makeDevice();
      final t0 = DateTime.utc(2026, 11, 22, 10, 0, 0);
      // 130 km/h = 36.1111 m/s => ~0.000324755 deg lat/sec
      const degLatPerSec = 36.111111 / 111194.9266;

      for (int s = 0; s <= 35; s++) {
        final t = t0.add(Duration(seconds: s));
        final pos = makePos(
          id: s + 1,
          fixTime: t,
          lat: 45.0 + s * degLatPerSec,
          lon: 11.0,
          speedKnots: 0.0,
        );
        tracker.recordPosition(pos, observedAt: t);
        if (s >= 2) {
          final snap = tracker.evaluate(device.id, pos, now: t);
          expect(snap.effectiveSpeedKmh, closeTo(130.0, 2.0));
          expect(snap.isSpeedFromDisplacement, isTrue);
          expect(
            markerSuffixFor(device, pos, motion: snap, now: t),
            'online',
            reason: 'Must remain online at t=${s}s',
          );
        }
      }
    });

    test('normal deceleration (50 -> 15 -> 0 km/h) turns static immediately', () {
      final tracker = DeviceMotionTracker();
      final device = makeDevice();
      final t0 = DateTime.utc(2026, 11, 22, 10, 5, 0);

      final p50 = makePos(
        id: 1,
        fixTime: t0,
        lat: 45.5,
        lon: 11.5,
        speedKnots: 50.0 / kKnotsToKmh,
      );
      tracker.recordPosition(p50, observedAt: t0);

      final t1 = t0.add(const Duration(seconds: 2));
      final p15 = makePos(
        id: 2,
        fixTime: t1,
        lat: 45.5,
        lon: 11.5,
        speedKnots: 15.0 / kKnotsToKmh,
      );
      tracker.recordPosition(p15, observedAt: t1);

      final t2 = t0.add(const Duration(seconds: 4));
      final p0 = makePos(
        id: 3,
        fixTime: t2,
        lat: 45.5,
        lon: 11.5,
        speedKnots: 0.0,
      );
      tracker.recordPosition(p0, observedAt: t2);

      final snap = tracker.evaluate(device.id, p0, now: t2);
      expect(snap.inHighSpeedGrace, isFalse);
      expect(markerSuffixFor(device, p0, motion: snap, now: t2), 'static');
      expect(
        buildDeviceStatusLabel(device, p0, motion: snap, now: t2),
        startsWith('Static '),
      );
    });

    test('abrupt stop from high speed (100 -> 0 km/h) holds grace <= 15s then turns static', () {
      final tracker = DeviceMotionTracker();
      final device = makeDevice();
      final t0 = DateTime.utc(2026, 11, 22, 10, 10, 0);

      final p100 = makePos(
        id: 1,
        fixTime: t0,
        lat: 45.5,
        lon: 11.5,
        speedKnots: 100.0 / kKnotsToKmh,
      );
      tracker.recordPosition(p100, observedAt: t0);

      final tDrop = t0.add(const Duration(seconds: 2));
      final p0 = makePos(
        id: 2,
        fixTime: tDrop,
        lat: 45.5,
        lon: 11.5,
        speedKnots: 0.0,
      );
      tracker.recordPosition(p0, observedAt: tDrop);

      final tInsideGrace = t0.add(const Duration(seconds: 10));
      final snapGrace = tracker.evaluate(device.id, p0, now: tInsideGrace);
      expect(snapGrace.inHighSpeedGrace, isTrue);
      expect(
        markerSuffixFor(device, p0, motion: snapGrace, now: tInsideGrace),
        'online',
      );
      expect(
        buildDeviceStatusLabel(device, p0, motion: snapGrace, now: tInsideGrace),
        'Moving 100.0 km/h',
      );

      final tAfterGrace = t0.add(const Duration(seconds: 16));
      final snapExpired = tracker.evaluate(device.id, p0, now: tAfterGrace);
      expect(snapExpired.inHighSpeedGrace, isFalse);
      expect(
        markerSuffixFor(device, p0, motion: snapExpired, now: tAfterGrace),
        'static',
      );
      expect(
        buildDeviceStatusLabel(device, p0, motion: snapExpired, now: tAfterGrace),
        startsWith('Static '),
      );
    });

    test('parked GPS jitter (5m in 1s) and LBS teleport (1000m in 2s) are rejected', () {
      final tracker = DeviceMotionTracker();
      final device = makeDevice();
      final t0 = DateTime.utc(2026, 11, 22, 10, 15, 0);

      for (int s = 0; s <= 4; s++) {
        final t = t0.add(Duration(seconds: s));
        tracker.recordPosition(
          makePos(id: s + 1, fixTime: t, lat: 45.0, lon: 11.0, speedKnots: 0.0),
          observedAt: t,
        );
      }

      // 5 m jitter in 1 s (~0.000045 deg lat)
      final tJitter = t0.add(const Duration(seconds: 5));
      final pJitter = makePos(
        id: 6,
        fixTime: tJitter,
        lat: 45.000045,
        lon: 11.0,
        speedKnots: 0.0,
      );
      tracker.recordPosition(pJitter, observedAt: tJitter);
      final snapJitter = tracker.evaluate(device.id, pJitter, now: tJitter);
      expect(snapJitter.effectiveSpeedKmh, 0.0);
      expect(
        markerSuffixFor(device, pJitter, motion: snapJitter, now: tJitter),
        'static',
      );

      // 1000 m LBS teleport in 2 s (~0.00899 deg lat => ~1800 km/h > 300 km/h)
      final tTeleport = t0.add(const Duration(seconds: 7));
      final pTeleport = makePos(
        id: 7,
        fixTime: tTeleport,
        lat: 45.009035,
        lon: 11.0,
        speedKnots: 0.0,
      );
      tracker.recordPosition(pTeleport, observedAt: tTeleport);
      final snapTeleport =
          tracker.evaluate(device.id, pTeleport, now: tTeleport);
      expect(snapTeleport.effectiveSpeedKmh, 0.0);
      expect(
        markerSuffixFor(device, pTeleport, motion: snapTeleport, now: tTeleport),
        'static',
      );
    });

    test('buffering gap (75s+) after high speed stays online, while offline status turns offline immediately', () {
      final tracker = DeviceMotionTracker();
      final onlineDevice = makeDevice(status: 'online');
      final offlineDevice = makeDevice(status: 'offline');
      final t0 = DateTime.utc(2026, 11, 22, 10, 20, 0);

      final pHigh = makePos(
        id: 1,
        fixTime: t0,
        lat: 45.5,
        lon: 11.5,
        speedKnots: 90.0 / kKnotsToKmh,
      );
      tracker.recordPosition(pHigh, observedAt: t0);

      final tGap75 = t0.add(const Duration(seconds: 75));
      final snap75 = tracker.evaluate(onlineDevice.id, pHigh, now: tGap75);
      expect(
        markerSuffixFor(onlineDevice, pHigh, motion: snap75, now: tGap75),
        'online',
      );

      final tGap150 = t0.add(const Duration(seconds: 150));
      final snap150 = tracker.evaluate(onlineDevice.id, pHigh, now: tGap150);
      expect(snap150.maxFreshFixMinutes, kHighSpeedFixFreshMinutes);
      expect(
        markerSuffixFor(onlineDevice, pHigh, motion: snap150, now: tGap150),
        'online',
      );
      expect(
        markerSuffixFor(offlineDevice, pHigh, motion: snap150, now: tGap150),
        'offline',
      );
    });

    test('future-drifted fixTime (+45s) does not freeze subsequent live packets', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = TraccarService.instance;
      await service.init();
      service.devices.clear();
      service.positions.clear();
      service.motionTracker.clear();

      final tNow = DateTime.utc(2026, 11, 22, 12, 0, 0);
      final pFuture = makePos(
        id: 100,
        fixTime: tNow.add(const Duration(seconds: 45)),
        lat: 45.5000,
        lon: 11.5000,
        speedKnots: 30.0,
      );
      expect(service.ingestPosition(pFuture, observedAt: tNow), isTrue);

      final tLater = tNow.add(const Duration(seconds: 2));
      final pLive = makePos(
        id: 101,
        fixTime: tLater,
        lat: 45.5010,
        lon: 11.5010,
        speedKnots: 30.0,
      );
      expect(service.ingestPosition(pLive, observedAt: tLater), isTrue);
      expect(service.positions[7]?.id, 101);
      expect(service.positions[7]?.latitude, 45.5010);
    });

    test('authoritative REST override always updates current position', () {
      final tNow = DateTime.utc(2026, 11, 22, 12, 5, 0);
      final current = makePos(
        id: 200,
        fixTime: tNow,
        lat: 45.5000,
        lon: 11.5000,
      );
      final olderRest = makePos(
        id: 201,
        fixTime: tNow.subtract(const Duration(seconds: 1)),
        lat: 45.5020,
        lon: 11.5020,
      );
      expect(
        shouldAcceptAsLatestPosition(
          current,
          olderRest,
          authoritative: true,
          currentObservedAt: tNow,
          now: tNow,
        ),
        isTrue,
      );
    });

    test('coarse LBS / invalid packets are rejected within 30s of valid GPS then accepted later', () {
      final tNow = DateTime.utc(2026, 11, 22, 12, 10, 0);
      final validGps = makePos(
        id: 300,
        fixTime: tNow,
        lat: 45.5000,
        lon: 11.5000,
        accuracy: 10.0,
        valid: true,
      );
      final coarseAccuracy = makePos(
        id: 301,
        fixTime: tNow.add(const Duration(seconds: 5)),
        lat: 45.5200,
        lon: 11.5200,
        accuracy: 600.0,
        valid: true,
      );
      final invalidGps = makePos(
        id: 302,
        fixTime: tNow.add(const Duration(seconds: 10)),
        lat: 45.5300,
        lon: 11.5300,
        accuracy: 10.0,
        valid: false,
      );

      expect(
        shouldAcceptAsLatestPosition(
          validGps,
          coarseAccuracy,
          currentObservedAt: tNow,
          now: tNow.add(const Duration(seconds: 5)),
        ),
        isFalse,
      );
      expect(
        shouldAcceptAsLatestPosition(
          validGps,
          invalidGps,
          currentObservedAt: tNow,
          now: tNow.add(const Duration(seconds: 10)),
        ),
        isFalse,
      );
      expect(
        shouldAcceptAsLatestPosition(
          validGps,
          coarseAccuracy,
          currentObservedAt: tNow,
          now: tNow.add(const Duration(seconds: 31)),
        ),
        isTrue,
      );
    });

    test('single GPS bounce (30m in 1s) while parked is rejected by two-step gate', () {
      final tracker = DeviceMotionTracker();
      final device = makeDevice();
      final t0 = DateTime.utc(2026, 11, 22, 12, 15, 0);

      for (int s = 0; s <= 5; s++) {
        final t = t0.add(Duration(seconds: s));
        tracker.recordPosition(
          makePos(id: s + 1, fixTime: t, lat: 45.0, lon: 11.0, speedKnots: 0.0),
          observedAt: t,
        );
      }

      // Single 30m spike in 1s (~0.00027 deg lat) while previously parked
      final tBounce = t0.add(const Duration(seconds: 6));
      final pBounce = makePos(
        id: 7,
        fixTime: tBounce,
        lat: 45.00027,
        lon: 11.0,
        speedKnots: 0.0,
      );
      tracker.recordPosition(pBounce, observedAt: tBounce);
      final snap = tracker.evaluate(device.id, pBounce, now: tBounce);
      expect(snap.effectiveSpeedKmh, 0.0);
      expect(
        markerSuffixFor(device, pBounce, motion: snap, now: tBounce),
        'static',
      );
    });
  });

  testWidgets('DevicesScreen ticks Static and Offline elapsed timers every 1 second without waiting for 5s refresh', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = TraccarService.instance;
    await service.init();
    service.devices.clear();
    service.positions.clear();
    service.motionTracker.clear();

    var fakeNow = DateTime(2026, 11, 22, 20, 0, 0);
    currentClock = () => fakeNow;
    addTearDown(() {
      currentClock = DateTime.now;
      service.devices.clear();
      service.positions.clear();
      service.motionTracker.clear();
    });

    final staticFixTime = fakeNow.subtract(const Duration(minutes: 10));
    final offlineUpdateTime = fakeNow.subtract(const Duration(hours: 1));

    service.devices[1] = TraccarDevice(
      id: 1,
      positionId: 10,
      name: 'Tracker Statico',
      uniqueId: '111111111111111',
      category: 'car',
      status: 'online',
      lastUpdate: staticFixTime,
      model: 'EV-201G',
      phone: null,
    );
    service.positions[1] = TraccarPosition(
      id: 10,
      deviceId: 1,
      fixTime: staticFixTime,
      outdated: false,
      valid: true,
      latitude: 45.5,
      longitude: 11.5,
      altitude: 30.0,
      speed: 0.0,
      course: 0.0,
      protocol: 'minifinder2',
      attributes: const <String, dynamic>{},
    );

    service.devices[2] = TraccarDevice(
      id: 2,
      positionId: 0,
      name: 'Tracker Offline',
      uniqueId: '222222222222222',
      category: 'car',
      status: 'offline',
      lastUpdate: offlineUpdateTime,
      model: 'EV-201G',
      phone: null,
    );

    await tester.pumpWidget(const MaterialApp(home: DevicesScreen()));
    await tester.pump();

    expect(find.text('Static 10min 0sec'), findsOneWidget);
    expect(find.text('Offline 1hr 0min 0sec'), findsOneWidget);

    fakeNow = fakeNow.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Static 10min 2sec'), findsOneWidget);
    expect(find.text('Offline 1hr 0min 2sec'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('DeviceInfoScreen shows position.fixTime as Last Update and device.lastUpdate as Last Contact', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final service = TraccarService.instance;
    await service.init();
    service.devices.clear();
    service.positions.clear();
    service.motionTracker.clear();

    addTearDown(() {
      service.devices.clear();
      service.positions.clear();
      service.motionTracker.clear();
    });

    final fixTime = DateTime(2026, 11, 25, 8, 47, 39);
    final lastContact = DateTime(2026, 11, 25, 8, 58, 25);

    service.devices[1] = TraccarDevice(
      id: 1,
      positionId: 10,
      name: 'Tracker Singolo',
      uniqueId: '111111111111111',
      category: 'car',
      status: 'online',
      lastUpdate: lastContact,
      model: 'EV-201G',
      phone: null,
    );
    service.positions[1] = TraccarPosition(
      id: 10,
      deviceId: 1,
      fixTime: fixTime,
      outdated: false,
      valid: true,
      latitude: 45.5,
      longitude: 11.5,
      altitude: 30.0,
      speed: 0.0,
      course: 0.0,
      protocol: 'minifinder2',
      attributes: const <String, dynamic>{},
    );

    await tester.pumpWidget(
      const MaterialApp(home: DeviceInfoScreen(deviceId: 1)),
    );
    await tester.pump();

    final lastUpdateRow = find.ancestor(
      of: find.text('Last Update'),
      matching: find.byType(Row),
    );
    final lastContactRow = find.ancestor(
      of: find.text('Last Contact'),
      matching: find.byType(Row),
    );

    expect(lastUpdateRow, findsOneWidget);
    expect(lastContactRow, findsOneWidget);
    expect(
      find.descendant(
        of: lastUpdateRow,
        matching: find.text(formatDateTime(fixTime)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lastContactRow,
        matching: find.text(formatDateTime(lastContact)),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
