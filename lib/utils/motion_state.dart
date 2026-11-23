import 'dart:math' as math;

import '../models/traccar_models.dart';

const double kMovingSpeedThresholdKmh = 3.0;
const double kHighSpeedThresholdKmh = 25.0;
const Duration kHighSpeedStopGrace = Duration(seconds: 15);
const int kNormalFixFreshMinutes = 1;
const int kHighSpeedFixFreshMinutes = 2;
const Duration kHighSpeedRecentWindow = Duration(minutes: 4);

const double kMaxGpsAccuracyMeters = 150.0;
const Duration kBurstDedupWindow = Duration(seconds: 3);
const Duration kLbsIgnoreGpsWindow = Duration(seconds: 30);

const double kMinStepSpeedKmh = 10.0;
const double kMinDisplacementSpeedKmh = 12.0;
const double kMaxRealisticSpeedKmh = 300.0;
const double kMinDisplacementMeters = 20.0;
const double kMaxStepDeltaSeconds = 30.0;
const double kPreferredSmoothMinSeconds = 3.0;
const double kPreferredSmoothMaxSeconds = 10.0;
const int kHistoryWindowSeconds = 45;
const int kMaxHistorySamples = 40;

const double _knotsToKmh = 1.852;

double _degToRad(double deg) => deg * (math.pi / 180.0);

/// Great-circle distance in meters using the Haversine formula.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadiusM = 6371000.0;
  final double dLat = _degToRad(lat2 - lat1);
  final double dLon = _degToRad(lon2 - lon1);
  final double rLat1 = _degToRad(lat1);
  final double rLat2 = _degToRad(lat2);

  final double sinLat = math.sin(dLat / 2.0);
  final double sinLon = math.sin(dLon / 2.0);
  final double a =
      sinLat * sinLat + math.cos(rLat1) * math.cos(rLat2) * sinLon * sinLon;
  final double c =
      2.0 * math.atan2(math.sqrt(a), math.sqrt(math.max(0.0, 1.0 - a)));
  return earthRadiusM * c;
}

bool _isValidGpsFix(TraccarPosition pos) {
  return pos.valid &&
      pos.accuracy <= kMaxGpsAccuracyMeters &&
      pos.fixTime != null &&
      pos.latitude.isFinite &&
      pos.longitude.isFinite &&
      (pos.latitude.abs() > 0.0001 || pos.longitude.abs() > 0.0001);
}

/// Guards live marker state against burst reordering and coarse LBS regressions
/// without freezing tracking when the device clock drifts ahead.
bool shouldAcceptAsLatestPosition(
  TraccarPosition? current,
  TraccarPosition incoming, {
  bool authoritative = false,
  DateTime? currentObservedAt,
  DateTime? now,
}) {
  if (authoritative || current == null) return true;
  if (incoming.id != 0 && incoming.id == current.id) return true;

  final DateTime tNow = now ?? DateTime.now();

  final bool currentIsFreshGps =
      current.valid && current.accuracy <= kMaxGpsAccuracyMeters;
  final bool incomingIsCoarseOrInvalid =
      !incoming.valid || incoming.accuracy > kMaxGpsAccuracyMeters;
  if (currentIsFreshGps &&
      incomingIsCoarseOrInvalid &&
      currentObservedAt != null &&
      !tNow.difference(currentObservedAt).isNegative &&
      tNow.difference(currentObservedAt) <= kLbsIgnoreGpsWindow) {
    return false;
  }

  if (incoming.outdated &&
      currentObservedAt != null &&
      !tNow.difference(currentObservedAt).isNegative &&
      tNow.difference(currentObservedAt) <= kLbsIgnoreGpsWindow) {
    return false;
  }

  if (incoming.fixTime == null || current.fixTime == null) return true;
  if (!incoming.fixTime!.isBefore(current.fixTime!)) return true;

  final bool currentFixInFuture =
      current.fixTime!.isAfter(tNow.add(const Duration(seconds: 5)));
  final bool withinBurst = currentObservedAt != null &&
      !tNow.difference(currentObservedAt).isNegative &&
      tNow.difference(currentObservedAt) <= kBurstDedupWindow;
  if (withinBurst && !currentFixInFuture) {
    return false;
  }
  return true;
}

class MotionSnapshot {
  final double effectiveSpeedKmh;
  final bool isSpeedFromDisplacement;
  final double lastConfirmedSpeedKmh;
  final bool inHighSpeedGrace;
  final bool hadRecentHighSpeed;

  const MotionSnapshot({
    required this.effectiveSpeedKmh,
    required this.isSpeedFromDisplacement,
    required this.lastConfirmedSpeedKmh,
    required this.inHighSpeedGrace,
    required this.hadRecentHighSpeed,
  });

  int get maxFreshFixMinutes =>
      hadRecentHighSpeed ? kHighSpeedFixFreshMinutes : kNormalFixFreshMinutes;

  double get displaySpeedKmh => effectiveSpeedKmh >= kMovingSpeedThresholdKmh
      ? effectiveSpeedKmh
      : (inHighSpeedGrace ? lastConfirmedSpeedKmh : effectiveSpeedKmh);
}

class _FixSample {
  final DateTime fixTime;
  final int fixTimeMs;
  final double lat;
  final double lon;

  const _FixSample({
    required this.fixTime,
    required this.fixTimeMs,
    required this.lat,
    required this.lon,
  });
}

class _DeviceMotionBuffer {
  final List<_FixSample> samples = <_FixSample>[];
  double lastConfirmedSpeedKmh = 0.0;
  DateTime? lastHighSpeedAt;
}

/// Tracks per-device valid GPS fixes to recover speed when firmware emits 0 at high speed.
class DeviceMotionTracker {
  final Map<int, _DeviceMotionBuffer> _buffers = <int, _DeviceMotionBuffer>{};

  void recordPosition(TraccarPosition pos, {DateTime? observedAt}) {
    final DateTime now = observedAt ?? DateTime.now();
    final _DeviceMotionBuffer buf =
        _buffers.putIfAbsent(pos.deviceId, _DeviceMotionBuffer.new);

    final bool isLatest = pos.fixTime == null ||
        buf.samples.isEmpty ||
        !pos.fixTime!.isBefore(buf.samples.last.fixTime);

    if (_isValidGpsFix(pos)) {
      final DateTime fixTime = pos.fixTime!;
      final int fixTimeMs = fixTime.millisecondsSinceEpoch;
      final _FixSample sample = _FixSample(
        fixTime: fixTime,
        fixTimeMs: fixTimeMs,
        lat: pos.latitude,
        lon: pos.longitude,
      );

      final int existingIdx =
          buf.samples.indexWhere((s) => s.fixTimeMs == fixTimeMs);
      if (existingIdx >= 0) {
        buf.samples[existingIdx] = sample;
      } else {
        buf.samples.add(sample);
        buf.samples.sort((a, b) => a.fixTimeMs.compareTo(b.fixTimeMs));
      }

      final int cutoffMs =
          buf.samples.last.fixTimeMs - (kHistoryWindowSeconds * 1000);
      buf.samples.removeWhere((s) => s.fixTimeMs < cutoffMs);
      if (buf.samples.length > kMaxHistorySamples) {
        buf.samples.removeRange(0, buf.samples.length - kMaxHistorySamples);
      }
    }

    if (isLatest) {
      final ({double speedKmh, bool fromDisplacement}) computed =
          _computeSpeed(buf, pos, now);
      final double eff = computed.speedKmh;
      if (eff >= kHighSpeedThresholdKmh) {
        buf.lastConfirmedSpeedKmh = eff;
        buf.lastHighSpeedAt = now;
      } else if (eff >= kMovingSpeedThresholdKmh) {
        buf.lastConfirmedSpeedKmh = eff;
        // Clear high-speed grace during normal deceleration so real stops turn static immediately.
        buf.lastHighSpeedAt = null;
      }
    }
  }

  MotionSnapshot evaluate(
    int deviceId,
    TraccarPosition? pos, {
    DateTime? now,
  }) {
    final DateTime tNow = now ?? DateTime.now();
    final _DeviceMotionBuffer? buf = _buffers[deviceId];
    final ({double speedKmh, bool fromDisplacement}) computed =
        _computeSpeed(buf, pos, tNow);
    final double eff = computed.speedKmh;

    final DateTime? highSpeedAt = buf?.lastHighSpeedAt;
    final Duration? elapsedSinceHigh =
        highSpeedAt != null ? tNow.difference(highSpeedAt) : null;
    final bool inGrace = eff < kMovingSpeedThresholdKmh &&
        elapsedSinceHigh != null &&
        !elapsedSinceHigh.isNegative &&
        elapsedSinceHigh <= kHighSpeedStopGrace;
    final bool recentHigh = elapsedSinceHigh != null &&
        !elapsedSinceHigh.isNegative &&
        elapsedSinceHigh <= kHighSpeedRecentWindow;

    return MotionSnapshot(
      effectiveSpeedKmh: eff,
      isSpeedFromDisplacement: computed.fromDisplacement,
      lastConfirmedSpeedKmh: buf?.lastConfirmedSpeedKmh ?? 0.0,
      inHighSpeedGrace: inGrace,
      hadRecentHighSpeed: recentHigh,
    );
  }

  ({double speedKmh, bool fromDisplacement}) _computeSpeed(
    _DeviceMotionBuffer? buf,
    TraccarPosition? pos,
    DateTime tNow,
  ) {
    if (pos == null) {
      return (speedKmh: 0.0, fromDisplacement: false);
    }

    final double reported =
        pos.speed.isFinite && pos.speed > 0 ? pos.speed * _knotsToKmh : 0.0;
    if (reported >= kMovingSpeedThresholdKmh) {
      return (speedKmh: reported, fromDisplacement: false);
    }

    if (buf != null && _isValidGpsFix(pos)) {
      final int posFixMs = pos.fixTime!.millisecondsSinceEpoch;

      // Stage 1: latest interval check rejects stationary stops and LBS teleports immediately.
      _FixSample? prev;
      int prevIdx = -1;
      for (int i = buf.samples.length - 1; i >= 0; i--) {
        if (buf.samples[i].fixTimeMs < posFixMs) {
          prev = buf.samples[i];
          prevIdx = i;
          break;
        }
      }
      if (prev == null) {
        return (speedKmh: reported, fromDisplacement: false);
      }

      final double dtLatest = (posFixMs - prev.fixTimeMs) / 1000.0;
      if (dtLatest < 0.5 || dtLatest > kMaxStepDeltaSeconds) {
        return (speedKmh: reported, fromDisplacement: false);
      }
      final double latestDist = haversineMeters(
        prev.lat,
        prev.lon,
        pos.latitude,
        pos.longitude,
      );
      final double latestSpeed = (latestDist / dtLatest) * 3.6;
      if (latestSpeed < kMinStepSpeedKmh ||
          latestSpeed > kMaxRealisticSpeedKmh) {
        return (speedKmh: reported, fromDisplacement: false);
      }

      // Anti-spike gate: require recent high-speed cruise (>= 50 km/h) or 2 consecutive moving steps.
      bool confirmedByHistory = buf.lastConfirmedSpeedKmh >= 50.0 &&
          buf.lastHighSpeedAt != null &&
          !tNow.difference(buf.lastHighSpeedAt!).isNegative &&
          tNow.difference(buf.lastHighSpeedAt!) <= const Duration(minutes: 2);
      if (!confirmedByHistory) {
        for (int j = prevIdx - 1; j >= 0; j--) {
          final double prevDt =
              (prev.fixTimeMs - buf.samples[j].fixTimeMs) / 1000.0;
          if (prevDt < 0.5) continue;
          if (prevDt <= kMaxStepDeltaSeconds) {
            final double prevDist = haversineMeters(
              buf.samples[j].lat,
              buf.samples[j].lon,
              prev.lat,
              prev.lon,
            );
            final double prevSpeed = (prevDist / prevDt) * 3.6;
            if (prevSpeed >= kMinStepSpeedKmh &&
                prevSpeed <= kMaxRealisticSpeedKmh) {
              confirmedByHistory = true;
            }
          }
          break;
        }
      }
      if (!confirmedByHistory) {
        return (speedKmh: reported, fromDisplacement: false);
      }

      // Stage 2: smoothed window (~3..10 s, closest to 5 s) suppresses 1 s GPS jitter.
      _FixSample ref = prev;
      double bestDiff = double.infinity;
      for (final _FixSample s in buf.samples) {
        if (s.fixTimeMs >= posFixMs) break;
        final double dt = (posFixMs - s.fixTimeMs) / 1000.0;
        if (dt >= kPreferredSmoothMinSeconds &&
            dt <= kPreferredSmoothMaxSeconds) {
          final double diff = (dt - 5.0).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            ref = s;
          }
        }
      }

      final double refDt = (posFixMs - ref.fixTimeMs) / 1000.0;
      if (refDt >= 0.5) {
        final double refDist = haversineMeters(
          ref.lat,
          ref.lon,
          pos.latitude,
          pos.longitude,
        );
        final double refSpeed = (refDist / refDt) * 3.6;
        if (refDist >= kMinDisplacementMeters &&
            refSpeed >= kMinDisplacementSpeedKmh &&
            refSpeed <= kMaxRealisticSpeedKmh) {
          return (speedKmh: refSpeed, fromDisplacement: true);
        }
      }
    }

    return (speedKmh: reported, fromDisplacement: false);
  }

  void clear() {
    _buffers.clear();
  }
}
