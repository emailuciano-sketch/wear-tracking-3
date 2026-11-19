import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MarkerIconCache {
  MarkerIconCache._();
  static final MarkerIconCache instance = MarkerIconCache._();

  final Map<String, BitmapDescriptor> _cache = <String, BitmapDescriptor>{};

  Future<BitmapDescriptor> getMarkerIcon({
    required String category,
    required String suffix,
    int? targetSize,
  }) async {
    final size = targetSize ?? (suffix == 'online' ? 104 : 90);
    final key = '${category}_${suffix}_$size';
    final cached = _cache[key];
    if (cached != null) return cached;

    final candidates = <String>[
      'assets/markers/marker_${category}_$suffix.png',
      'assets/markers/marker_default_$suffix.png',
      'assets/markers/marker_default_static.png',
    ];

    ByteData? data;
    for (final path in candidates) {
      try {
        data = await rootBundle.load(path);
        break;
      } catch (_) {
        // Fallback to next candidate.
      }
    }

    if (data == null) {
      return BitmapDescriptor.defaultMarker;
    }

    final descriptor = await _decodeResized(
      data.buffer.asUint8List(),
      size,
      size,
    );
    _cache[key] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> getImageAssetIcon(
    String assetPath, {
    int width = 80,
    int height = 80,
  }) async {
    final key = '${assetPath}_${width}x$height';
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final data = await rootBundle.load(assetPath);
      final descriptor = await _decodeResized(
        data.buffer.asUint8List(),
        width,
        height,
      );
      _cache[key] = descriptor;
      return descriptor;
    } catch (_) {
      return BitmapDescriptor.defaultMarker;
    }
  }

  Future<BitmapDescriptor> _decodeResized(
    Uint8List rawBytes,
    int width,
    int height,
  ) async {
    final codec = await ui.instantiateImageCodec(
      rawBytes,
      targetWidth: width,
      targetHeight: height,
    );
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    frame.image.dispose();
    if (byteData == null) {
      return BitmapDescriptor.defaultMarker;
    }
    final bytes = byteData.buffer.asUint8List();
    if (Platform.isIOS) {
      return BitmapDescriptor.bytes(bytes, width: width / 2.75);
    }
    return BitmapDescriptor.bytes(bytes, bitmapScaling: MapBitmapScaling.none);
  }
}

