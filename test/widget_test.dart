import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wear_tracking_flutter/models/traccar_models.dart';
import 'package:wear_tracking_flutter/screens/login_screen.dart';
import 'package:wear_tracking_flutter/screens/settings_screen.dart';
import 'package:wear_tracking_flutter/services/traccar_service.dart';
import 'package:wear_tracking_flutter/utils/formatters.dart';
import 'package:wear_tracking_flutter/utils/marker_interpolation.dart';

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

  testWidgets('Server Settings dialog saves https URL and closes without assertion errors', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await TraccarService.instance.init();

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('Server Settings'));
    await tester.pumpAndSettle();

    final textField = find.widgetWithText(TextField, 'Server URL');
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'https://pedinatore.com/');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(TraccarService.instance.serverUrl, 'https://pedinatore.com');
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

  test('adaptive interval smoothing clamps bounds and ignores idle gaps', () {
    final first = updateSmoothedIntervalMs(
      currentSmoothedMs: null,
      observedDeltaMs: 2000,
    );
    expect(first, 2000.0);

    final second = updateSmoothedIntervalMs(
      currentSmoothedMs: first,
      observedDeltaMs: 3000,
    );
    expect(second, closeTo(2350.0, 1e-6));
    expect(durationMsFromSmoothedInterval(second), 2468);

    // Idle gaps (> 12000 ms) must not skew the smoothed interval.
    final afterIdle = updateSmoothedIntervalMs(
      currentSmoothedMs: second,
      observedDeltaMs: 60000,
    );
    expect(afterIdle, second);

    // Sub-second bursts are clamped at minimum 800 ms, very slow at 4500 ms.
    final clampedLow = updateSmoothedIntervalMs(
      currentSmoothedMs: null,
      observedDeltaMs: 300,
    );
    expect(clampedLow, kMinMarkerAnimDurationMs.toDouble());
    expect(durationMsFromSmoothedInterval(6000.0), kMaxMarkerAnimDurationMs);
  });

  test('shouldSnapToPosition snaps only large GPS jumps (> 500 m)', () {
    const origin = LatLng(45.4642, 9.1900);
    const shortHop = LatLng(45.4650, 9.1900); // ~89 m
    const longJump = LatLng(45.4742, 9.1900); // ~1.11 km
    expect(shouldSnapToPosition(origin, shortHop), isFalse);
    expect(shouldSnapToPosition(origin, longJump), isTrue);
  });
}
