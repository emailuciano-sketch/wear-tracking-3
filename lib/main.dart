import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final GoogleMapsFlutterPlatform mapsImplementation =
      GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    mapsImplementation.useAndroidViewSurface = true;
    mapsImplementation
        .initializeWithRenderer(AndroidMapRenderer.latest)
        .catchError((_) => AndroidMapRenderer.platformDefault);
  }
  runApp(const WearTrackingApp());
}

class WearTrackingApp extends StatelessWidget {
  const WearTrackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wear-Tracking 4',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        primaryColor: const Color(0xFF007AA5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AA5),
          primary: const Color(0xFF007AA5),
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const SplashScreen(),
    );
  }
}
