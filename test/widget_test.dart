import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wear_tracking_flutter/models/traccar_models.dart';
import 'package:wear_tracking_flutter/screens/login_screen.dart';
import 'package:wear_tracking_flutter/screens/settings_screen.dart';
import 'package:wear_tracking_flutter/services/traccar_service.dart';
import 'package:wear_tracking_flutter/utils/formatters.dart';

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
}
