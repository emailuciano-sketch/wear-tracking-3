class TraccarUser {
  final int id;
  final String name;
  final String email;
  final String login;
  final String? phone;
  final bool readonly;
  final bool administrator;
  final String? map;
  final double latitude;
  final double longitude;
  final int zoom;
  final bool twelveHourFormat;
  final String? coordinateFormat;
  final bool disabled;
  final String? expirationTime;
  final int deviceLimit;
  final int userLimit;
  final bool deviceReadonly;
  final String? token;
  final bool limitCommands;
  final String? poiLayer;
  final Map<String, dynamic> attributes;
  final Map<String, dynamic> rawJson;

  TraccarUser({
    required this.id,
    required this.name,
    required this.email,
    required this.login,
    required this.phone,
    required this.readonly,
    required this.administrator,
    required this.map,
    required this.latitude,
    required this.longitude,
    required this.zoom,
    required this.twelveHourFormat,
    required this.coordinateFormat,
    required this.disabled,
    required this.expirationTime,
    required this.deviceLimit,
    required this.userLimit,
    required this.deviceReadonly,
    required this.token,
    required this.limitCommands,
    required this.poiLayer,
    required this.attributes,
    required this.rawJson,
  });

  factory TraccarUser.fromJson(Map<String, dynamic> json) {
    return TraccarUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      login: json['login']?.toString() ?? '',
      phone: json['phone']?.toString(),
      readonly: json['readonly'] == true,
      administrator: json['administrator'] == true,
      map: json['map']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      zoom: ((json['zoom'] as num?)?.toInt() ?? 0) > 0
          ? (json['zoom'] as num).toInt()
          : 6,
      twelveHourFormat: json['twelveHourFormat'] == true,
      coordinateFormat: json['coordinateFormat']?.toString(),
      disabled: json['disabled'] == true,
      expirationTime: json['expirationTime']?.toString(),
      deviceLimit: (json['deviceLimit'] as num?)?.toInt() ?? 0,
      userLimit: (json['userLimit'] as num?)?.toInt() ?? 0,
      deviceReadonly: json['deviceReadonly'] == true,
      token: json['token']?.toString(),
      limitCommands: json['limitCommands'] == true,
      poiLayer: json['poiLayer']?.toString(),
      attributes: json['attributes'] is Map
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : <String, dynamic>{},
      rawJson: Map<String, dynamic>.from(json),
    );
  }
}

class TraccarDevice {
  final int id;
  final int positionId;
  final String name;
  final String uniqueId;
  final String category;
  final String status;
  final DateTime? lastUpdate;
  final String? model;
  final String? phone;

  TraccarDevice({
    required this.id,
    required this.positionId,
    required this.name,
    required this.uniqueId,
    required this.category,
    required this.status,
    required this.lastUpdate,
    required this.model,
    required this.phone,
  });

  factory TraccarDevice.fromJson(Map<String, dynamic> json) {
    return TraccarDevice(
      id: (json['id'] as num?)?.toInt() ?? 0,
      positionId: (json['positionId'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? 'Device',
      uniqueId: json['uniqueId']?.toString() ?? '',
      category: (json['category']?.toString().isNotEmpty ?? false)
          ? json['category'].toString()
          : 'default',
      status: json['status']?.toString() ?? 'unknown',
      lastUpdate: json['lastUpdate'] != null
          ? DateTime.tryParse(json['lastUpdate'].toString())
          : null,
      model: json['model']?.toString(),
      phone: json['phone']?.toString(),
    );
  }
}

class TraccarPosition {
  final int id;
  final int deviceId;
  final DateTime? fixTime;
  final bool outdated;
  final bool valid;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed; // in knots
  final double course;
  final double accuracy;
  final String? protocol;
  final Map<String, dynamic> attributes;
  final Map<String, dynamic>? network;

  TraccarPosition({
    required this.id,
    required this.deviceId,
    required this.fixTime,
    required this.outdated,
    required this.valid,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.course,
    this.accuracy = 0.0,
    this.protocol,
    required this.attributes,
    this.network,
  });

  factory TraccarPosition.fromJson(Map<String, dynamic> json) {
    final rawTime = json['fixTime'] ?? json['deviceTime'] ?? json['serverTime'];
    return TraccarPosition(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      fixTime: rawTime != null ? DateTime.tryParse(rawTime.toString()) : null,
      outdated: json['outdated'] == true,
      valid: json['valid'] != false,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      course: (json['course'] as num?)?.toDouble() ?? 0.0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      protocol: json['protocol']?.toString(),
      attributes: json['attributes'] is Map
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : <String, dynamic>{},
      network: json['network'] is Map
          ? Map<String, dynamic>.from(json['network'] as Map)
          : null,
    );
  }
}

class SummaryReport {
  final int deviceId;
  final String deviceName;
  final double maxSpeed; // knots
  final double averageSpeed; // knots
  final double distance; // meters
  final int engineHours; // ms

  SummaryReport({
    required this.deviceId,
    required this.deviceName,
    required this.maxSpeed,
    required this.averageSpeed,
    required this.distance,
    required this.engineHours,
  });

  factory SummaryReport.fromJson(Map<String, dynamic> json) {
    return SummaryReport(
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      deviceName: json['deviceName']?.toString() ?? '',
      maxSpeed: (json['maxSpeed'] as num?)?.toDouble() ?? 0.0,
      averageSpeed: (json['averageSpeed'] as num?)?.toDouble() ?? 0.0,
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      engineHours: (json['engineHours'] as num?)?.toInt() ?? 0,
    );
  }
}

class TripReport {
  final int deviceId;
  final String deviceName;
  final double maxSpeed; // knots
  final double averageSpeed; // knots
  final double distance; // meters
  final int duration; // ms
  final DateTime? startTime;
  final DateTime? endTime;
  final double startLatitude;
  final double startLongitude;
  final double endLatitude;
  final double endLongitude;

  TripReport({
    required this.deviceId,
    required this.deviceName,
    required this.maxSpeed,
    required this.averageSpeed,
    required this.distance,
    required this.duration,
    required this.startTime,
    required this.endTime,
    required this.startLatitude,
    required this.startLongitude,
    required this.endLatitude,
    required this.endLongitude,
  });

  factory TripReport.fromJson(Map<String, dynamic> json) {
    return TripReport(
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      deviceName: json['deviceName']?.toString() ?? '',
      maxSpeed: (json['maxSpeed'] as num?)?.toDouble() ?? 0.0,
      averageSpeed: (json['averageSpeed'] as num?)?.toDouble() ?? 0.0,
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      startTime: json['startTime'] != null
          ? DateTime.tryParse(json['startTime'].toString())
          : null,
      endTime: json['endTime'] != null
          ? DateTime.tryParse(json['endTime'].toString())
          : null,
      startLatitude: (json['startLat'] as num?)?.toDouble() ??
          (json['startLatitude'] as num?)?.toDouble() ??
          0.0,
      startLongitude: (json['startLon'] as num?)?.toDouble() ??
          (json['startLongitude'] as num?)?.toDouble() ??
          0.0,
      endLatitude: (json['endLat'] as num?)?.toDouble() ??
          (json['endLatitude'] as num?)?.toDouble() ??
          0.0,
      endLongitude: (json['endLon'] as num?)?.toDouble() ??
          (json['endLongitude'] as num?)?.toDouble() ??
          0.0,
    );
  }
}

class StopReportModel {
  final int deviceId;
  final String deviceName;
  final int positionId;
  final int duration; // ms
  final DateTime? startTime;
  final DateTime? endTime;
  final double latitude;
  final double longitude;

  StopReportModel({
    required this.deviceId,
    required this.deviceName,
    required this.positionId,
    required this.duration,
    required this.startTime,
    required this.endTime,
    required this.latitude,
    required this.longitude,
  });

  factory StopReportModel.fromJson(Map<String, dynamic> json) {
    return StopReportModel(
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      deviceName: json['deviceName']?.toString() ?? '',
      positionId: (json['positionId'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      startTime: json['startTime'] != null
          ? DateTime.tryParse(json['startTime'].toString())
          : null,
      endTime: json['endTime'] != null
          ? DateTime.tryParse(json['endTime'].toString())
          : null,
      latitude: (json['latitude'] as num?)?.toDouble() ??
          (json['lat'] as num?)?.toDouble() ??
          0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ??
          (json['lon'] as num?)?.toDouble() ??
          0.0,
    );
  }
}

class DeviceEventModel {
  final int id;
  final int deviceId;
  final int positionId;
  final String type;
  final DateTime? serverTime;
  final Map<String, dynamic> attributes;

  DeviceEventModel({
    required this.id,
    required this.deviceId,
    required this.positionId,
    required this.type,
    required this.serverTime,
    required this.attributes,
  });

  factory DeviceEventModel.fromJson(Map<String, dynamic> json) {
    return DeviceEventModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceId: (json['deviceId'] as num?)?.toInt() ?? 0,
      positionId: (json['positionId'] as num?)?.toInt() ?? 0,
      type: json['type']?.toString() ?? '',
      serverTime: json['serverTime'] != null
          ? DateTime.tryParse(json['serverTime'].toString())
          : null,
      attributes: json['attributes'] is Map
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : <String, dynamic>{},
    );
  }
}

class RoutePoint {
  final int id;
  final DateTime? fixTime;
  final double latitude;
  final double longitude;
  final double speed; // knots
  final double course;
  final Map<String, dynamic> attributes;

  RoutePoint({
    required this.id,
    required this.fixTime,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.course,
    required this.attributes,
  });

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    final rawTime = json['fixTime'] ?? json['deviceTime'];
    return RoutePoint(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fixTime: rawTime != null ? DateTime.tryParse(rawTime.toString()) : null,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      course: (json['course'] as num?)?.toDouble() ?? 0.0,
      attributes: json['attributes'] is Map
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : <String, dynamic>{},
    );
  }
}
