import 'package:intl/intl.dart';
import '../models/traccar_models.dart';

const double kKnotsToKmh = 1.852;

double knotsToKmh(double knots) => knots * kKnotsToKmh;

int minutesSinceFix(DateTime? fixTime) {
  if (fixTime == null) return 0;
  final diff = DateTime.now().difference(fixTime.toLocal());
  return diff.inMinutes < 0 ? 0 : diff.inMinutes;
}

bool isDeviceMoving(TraccarDevice? device, TraccarPosition? position) {
  if (device == null || position == null) return false;
  final speedKmh = knotsToKmh(position.speed);
  final min = minutesSinceFix(position.fixTime);
  return device.status == 'online' && speedKmh >= 3.0 && min <= 1;
}

String markerSuffixFor(TraccarDevice? device, TraccarPosition? position) {
  if (device == null) return 'static';
  if (position != null && isDeviceMoving(device, position)) {
    return 'online';
  }
  if (device.status == 'online' || device.status == 'unknown') {
    return 'static';
  }
  return 'offline';
}

String formatTimeDiff(DateTime? fixTime) {
  if (fixTime == null) return '0min 0sec';
  final diff = DateTime.now().difference(fixTime.toLocal());
  final totalSeconds = diff.inSeconds < 0 ? 0 : diff.inSeconds;
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final mins = (totalSeconds % 3600) ~/ 60;
  final secs = totalSeconds % 60;

  if (days == 0 && hours != 0) {
    return '${hours}hr ${mins}min ${secs}sec';
  } else if (days == 0) {
    return '${mins}min ${secs}sec';
  }
  return '${days}days ${hours}hr ${mins}min ${secs}sec';
}

String buildDeviceStatusLabel(TraccarDevice device, TraccarPosition? position) {
  final speedKmh = position != null ? knotsToKmh(position.speed) : 0.0;
  final min = minutesSinceFix(position?.fixTime);
  final diff = formatTimeDiff(position?.fixTime);

  if (device.status == 'online' && speedKmh < 3.0) {
    return 'Static $diff';
  } else if (device.status == 'online' && min > 1) {
    return 'Static $diff';
  } else if (device.status == 'online' && min <= 1) {
    return 'Moving ${speedKmh.toStringAsFixed(1)} km/h';
  } else if (device.status == 'unknown') {
    return 'Unknown $diff';
  }
  return 'Offline $diff';
}

String formatDateTime(DateTime? dt) {
  if (dt == null) return '--';
  return DateFormat('dd-MM-yyyy hh:mm:ss a').format(dt.toLocal());
}

String formatIsoUtc(DateTime dt) {
  final utc = dt.toUtc();
  return DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(utc);
}

String formatDurationMs(int ms) {
  if (ms <= 0) return '0hr 0Min';
  final hours = ms ~/ 3600000;
  final mins = (ms % 3600000) ~/ 60000;
  return '${hours}hr ${mins}Min';
}

String compassDirection(double course) {
  if (course >= 15 && course < 75) return 'NE';
  if (course >= 75 && course < 105) return 'E';
  if (course >= 105 && course < 165) return 'SE';
  if (course >= 165 && course < 195) return 'S';
  if (course >= 195 && course < 255) return 'SW';
  if (course >= 255 && course < 285) return 'W';
  if (course >= 285 && course < 345) return 'NW';
  return 'N';
}

String capitalizeWord(String str) {
  if (str.isEmpty) return str;
  return str[0].toUpperCase() + str.substring(1);
}

String? formatGsmSignal(TraccarPosition? position) {
  if (position == null) return null;
  final attrs = position.attributes;

  // 1) Direct Traccar attributes (e.g. minifinder -> rssi: 0..31, or dBm / %)
  final rawAttr =
      attrs['rssi'] ?? attrs['gsm'] ?? attrs['gsmSignal'] ?? attrs['signal'];
  if (rawAttr is num) {
    return _formatRawGsmValue(rawAttr.toDouble());
  }

  // 2) EV-07B / minifinder2 protocol: GSM CSQ (0..31) is encoded in status bits 19..23
  if (position.protocol?.toLowerCase() == 'minifinder2' &&
      attrs['status'] is num) {
    final statusInt = (attrs['status'] as num).toInt();
    final csq = (statusInt >> 19) & 0x1F;
    return _formatRawGsmValue(csq.toDouble());
  }

  // 3) Traccar network.cellTowers[].signalStrength (dBm)
  final towers = position.network?['cellTowers'];
  if (towers is List && towers.isNotEmpty && towers.first is Map) {
    final first = towers.first as Map;
    final strength = first['signalStrength'];
    if (strength is num) {
      return _formatRawGsmValue(strength.toDouble());
    }
  }

  return null;
}

String? _formatRawGsmValue(double value) {
  if (value.isNaN || value.isInfinite) return null;
  // Standard AT+CSQ unknown sentinel
  if (value.round() == 99) return null;
  // Negative dBm value (e.g. -113..-51 dBm)
  if (value < 0) {
    final dbm = value.round();
    final percent = (((dbm + 113) / 62.0) * 100).round().clamp(0, 100);
    return '$percent% ($dbm dBm)';
  }
  // Standard GSM CSQ scale 0..31 -> dBm = -113 + 2 * CSQ
  if (value <= 31) {
    final csq = value.round().clamp(0, 31);
    final percent = ((csq / 31.0) * 100).round().clamp(0, 100);
    final dbm = -113 + (csq * 2);
    return '$percent% ($dbm dBm)';
  }
  // Percentage scale (32..100)
  if (value <= 100) {
    return '${value.round()}%';
  }
  return value.toStringAsFixed(0);
}
