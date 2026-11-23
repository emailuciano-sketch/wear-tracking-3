import 'package:material_ui/material_ui.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF007AA5),
        foregroundColor: Colors.white,
        title: const Text('About'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Wear-Tracking 4',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Center(
              child: Image.asset(
                'assets/images/logo.png',
                height: 100,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(height: 60),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Contact us',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Wear-Tracking 4 Flutter Edition (Android / iOS)',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
