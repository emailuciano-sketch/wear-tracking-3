import 'package:material_ui/material_ui.dart';

import '../services/traccar_service.dart';
import 'login_screen.dart';
import 'map_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final service = TraccarService.instance;
    await service.init();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    if (service.isAuthenticatedPref &&
        service.email.isNotEmpty &&
        service.password.isNotEmpty) {
      try {
        await service.login(service.email, service.password);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const MapScreen()),
        );
      } on UnauthorizedException {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        );
      } catch (_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const MapScreen()),
        );
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Image.asset(
            'assets/images/logo.png',
            height: 140,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              'Wear-Tracking 3',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF007AA5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
