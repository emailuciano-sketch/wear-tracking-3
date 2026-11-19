import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class MapLinks {
  static Future<void> openStreetView(
    BuildContext context, {
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=$latitude,$longitude',
    );
    await _launchExternal(context, uri);
  }

  static Future<void> openDirections(
    BuildContext context, {
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude',
    );
    await _launchExternal(context, uri);
  }

  static Future<void> _launchExternal(BuildContext context, Uri uri) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire Google Maps')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile aprire Google Maps')),
        );
      }
    }
  }
}
