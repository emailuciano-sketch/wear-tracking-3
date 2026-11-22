import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

const int kDefaultMarkerAnimDurationMs = 1500;
const int kMinMarkerAnimDurationMs = 800;
const int kMaxMarkerAnimDurationMs = 4500;
const int kMaxValidIntervalDeltaMs = 12000;
const double kSnapJumpDistanceMeters = 500.0;
const int kMarkerAnimFrameIntervalMs = 33;

const double _kEarthRadiusMeters = 6371000.0;

double haversineDistanceMeters(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180.0;
  final lat2 = b.latitude * math.pi / 180.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
  final dLng = (b.longitude - a.longitude) * math.pi / 180.0;

  final sinHalfLat = math.sin(dLat / 2.0);
  final sinHalfLng = math.sin(dLng / 2.0);
  final h = sinHalfLat * sinHalfLat +
      math.cos(lat1) * math.cos(lat2) * sinHalfLng * sinHalfLng;
  final c = 2.0 * math.atan2(math.sqrt(h), math.sqrt((1.0 - h).clamp(0.0, 1.0)));
  return _kEarthRadiusMeters * c;
}

bool shouldSnapToPosition(LatLng a, LatLng b) =>
    haversineDistanceMeters(a, b) > kSnapJumpDistanceMeters;

double updateSmoothedIntervalMs({
  required double? currentSmoothedMs,
  required int observedDeltaMs,
}) {
  if (observedDeltaMs <= 0 || observedDeltaMs > kMaxValidIntervalDeltaMs) {
    return currentSmoothedMs ?? kDefaultMarkerAnimDurationMs.toDouble();
  }
  if (currentSmoothedMs == null) {
    return observedDeltaMs
        .clamp(kMinMarkerAnimDurationMs, kMaxMarkerAnimDurationMs)
        .toDouble();
  }
  return (currentSmoothedMs * 0.65 + observedDeltaMs * 0.35).clamp(
    kMinMarkerAnimDurationMs.toDouble(),
    kMaxMarkerAnimDurationMs.toDouble(),
  );
}

int durationMsFromSmoothedInterval(double smoothedMs) =>
    (smoothedMs * 1.05)
        .round()
        .clamp(kMinMarkerAnimDurationMs, kMaxMarkerAnimDurationMs);

LatLng interpolateLatLng(double fraction, LatLng a, LatLng b) {
  if (fraction <= 0.0) return a;
  if (fraction >= 1.0) return b;

  final lat = (b.latitude - a.latitude) * fraction + a.latitude;
  var lngDelta = b.longitude - a.longitude;
  if (lngDelta.abs() > 180.0) {
    lngDelta -= lngDelta.sign * 360.0;
  }
  var lng = lngDelta * fraction + a.longitude;
  if (lng > 180.0) {
    lng -= 360.0;
  } else if (lng < -180.0) {
    lng += 360.0;
  }
  return LatLng(lat, lng);
}

double _normalizeAngle360(double deg) => (deg % 360.0 + 360.0) % 360.0;

double interpolateRotation(double fraction, double start, double end) {
  if (fraction <= 0.0) return _normalizeAngle360(start);
  if (fraction >= 1.0) return _normalizeAngle360(end);

  final normalizedDiff = ((end - start) + 360.0) % 360.0;
  final shortestDelta =
      normalizedDiff > 180.0 ? normalizedDiff - 360.0 : normalizedDiff;
  return _normalizeAngle360(fraction * shortestDelta + start);
}
