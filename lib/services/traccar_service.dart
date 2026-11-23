import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/traccar_models.dart';
import '../utils/motion_state.dart';

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = 'Unauthorized']);
  @override
  String toString() => message;
}

class TraccarService extends ChangeNotifier {
  TraccarService._();
  static final TraccarService instance = TraccarService._();

  static const String defaultServerUrl = 'https://pedinatore.com';
  static const String prefAuthenticated = 'authenticated';
  static const String prefEmail = 'email';
  static const String prefPassword = 'password';
  static const String prefMarkerLabel = 'marker_label';
  static const String prefSatelliteView = 'satellite_view';

  SharedPreferences? _prefs;
  HttpClient? _httpClient;
  final Map<String, String> _cookies = <String, String>{};

  TraccarUser? currentUser;
  final Map<int, TraccarDevice> devices = <int, TraccarDevice>{};
  final Map<int, TraccarPosition> positions = <int, TraccarPosition>{};
  final Map<int, DateTime> _positionObservedAt = <int, DateTime>{};
  final DeviceMotionTracker motionTracker = DeviceMotionTracker();

  bool _sessionValid = false;
  bool _isSyncActive = false;
  bool _isFetchingPositions = false;
  bool _lastFetchFailed = false;
  DateTime _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(0);

  WebSocket? _webSocket;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<dynamic>? _androidNetworkSub;
  String? _lastConnectivityKey;
  int _connectSeq = 0;

  static const EventChannel _androidNetworkChannel =
      EventChannel('com.wear.tracking.v4/network');

  final StreamController<void> _updateController =
      StreamController<void>.broadcast();
  Stream<void> get onLiveUpdate => _updateController.stream;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (!_prefs!.containsKey(prefMarkerLabel)) {
      await _prefs!.setBool(prefMarkerLabel, false);
    }
    if (!_prefs!.containsKey(prefSatelliteView)) {
      await _prefs!.setBool(prefSatelliteView, true);
    }
    _httpClient ??= _createHttpClient();
  }

  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    client.idleTimeout = const Duration(seconds: 15);
    return client;
  }

  String get serverUrl => defaultServerUrl;

  String get email => _prefs?.getString(prefEmail) ?? '';
  String get password => _prefs?.getString(prefPassword) ?? '';
  bool get isAuthenticatedPref => _prefs?.getBool(prefAuthenticated) ?? false;
  bool get markerLabel => _prefs?.getBool(prefMarkerLabel) ?? false;
  bool get satelliteView => _prefs?.getBool(prefSatelliteView) ?? true;

  Future<void> setMarkerLabel(bool value) async {
    await _prefs?.setBool(prefMarkerLabel, value);
    notifyListeners();
  }

  Future<void> setSatelliteView(bool value) async {
    await _prefs?.setBool(prefSatelliteView, value);
    notifyListeners();
  }

  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    await _prefs?.setString(prefEmail, email.trim());
    await _prefs?.setString(prefPassword, password);
    await _prefs?.setBool(prefAuthenticated, true);
  }

  void resetSession() {
    _sessionValid = false;
    currentUser = null;
    _cookies.clear();
  }

  void evictConnections() {
    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    _httpClient = _createHttpClient();
  }

  String? get _cookieHeader {
    if (_cookies.isEmpty) return null;
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _captureCookies(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      _cookies[cookie.name] = cookie.value;
    }
  }

  Future<TraccarUser> login(String userEmail, String userPassword) async {
    await init();
    evictConnections();
    _cookies.clear();
    _sessionValid = false;

    final uri = Uri.parse('$serverUrl/api/session');
    final request = await _httpClient!.postUrl(uri);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final body =
        'email=${Uri.encodeQueryComponent(userEmail.trim())}&password=${Uri.encodeQueryComponent(userPassword)}';
    request.write(body);

    final response = await request.close().timeout(const Duration(seconds: 12));
    _captureCookies(response);
    final responseBody = await utf8.decodeStream(response);

    if (response.statusCode == 200) {
      final map = jsonDecode(responseBody) as Map<String, dynamic>;
      currentUser = TraccarUser.fromJson(map);
      _sessionValid = true;
      await saveCredentials(email: userEmail, password: userPassword);
      return currentUser!;
    } else if (response.statusCode == 401) {
      throw UnauthorizedException('Credenziali non valide');
    } else {
      throw HttpException(
        'Errore server HTTP ${response.statusCode}',
        uri: uri,
      );
    }
  }

  Future<TraccarUser> ensureSession() async {
    if (_sessionValid && currentUser != null && _cookies.isNotEmpty) {
      return currentUser!;
    }
    if (email.isEmpty || password.isEmpty) {
      throw UnauthorizedException('Credenziali mancanti');
    }
    return login(email, password);
  }

  Future<dynamic> _authorizedGetJson(
    String pathAndQuery, {
    bool retryOn401 = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await ensureSession();
    final uri = Uri.parse('$serverUrl$pathAndQuery');
    final request = await _httpClient!.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final cookie = _cookieHeader;
    if (cookie != null) {
      request.headers.set(HttpHeaders.cookieHeader, cookie);
    }

    final response = await request.close().timeout(timeout);
    _captureCookies(response);
    final raw = await utf8.decodeStream(response);

    if (response.statusCode == 401 && retryOn401) {
      _sessionValid = false;
      await ensureSession();
      return _authorizedGetJson(
        pathAndQuery,
        retryOn401: false,
        timeout: timeout,
      );
    }
    if (response.statusCode == 401) {
      throw UnauthorizedException('Sessione scaduta');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    if (raw.trim().isEmpty) return <dynamic>[];
    return jsonDecode(raw);
  }

  Future<List<TraccarDevice>> getDevices() async {
    final decoded = await _authorizedGetJson('/api/devices');
    if (decoded is! List) return <TraccarDevice>[];
    final list = <TraccarDevice>[];
    for (final item in decoded) {
      if (item is Map) {
        final device = TraccarDevice.fromJson(
          Map<String, dynamic>.from(item),
        );
        devices[device.id] = device;
        list.add(device);
      }
    }
    return list;
  }

  bool ingestPosition(
    TraccarPosition pos, {
    bool authoritative = false,
    DateTime? observedAt,
  }) {
    final now = observedAt ?? DateTime.now();
    motionTracker.recordPosition(pos, observedAt: now);
    final current = positions[pos.deviceId];
    if (shouldAcceptAsLatestPosition(
      current,
      pos,
      authoritative: authoritative,
      currentObservedAt: _positionObservedAt[pos.deviceId],
      now: now,
    )) {
      positions[pos.deviceId] = pos;
      _positionObservedAt[pos.deviceId] = now;
      return true;
    }
    return false;
  }

  MotionSnapshot motionFor(
    int deviceId,
    TraccarPosition? position, {
    DateTime? now,
  }) {
    return motionTracker.evaluate(deviceId, position, now: now);
  }

  Future<List<TraccarPosition>> getLastPositions() async {
    final decoded = await _authorizedGetJson('/api/positions');
    if (decoded is! List) return <TraccarPosition>[];
    final list = <TraccarPosition>[];
    for (final item in decoded) {
      if (item is Map) {
        final pos = TraccarPosition.fromJson(
          Map<String, dynamic>.from(item),
        );
        ingestPosition(pos, authoritative: true);
        list.add(pos);
      }
    }
    return list;
  }

  Future<List<TraccarPosition>> getPositionsById(
    int deviceId,
    int positionId,
  ) async {
    final decoded = await _authorizedGetJson(
      '/api/positions?deviceId=$deviceId&id=$positionId',
    );
    if (decoded is! List) return <TraccarPosition>[];
    return decoded
        .whereType<Map>()
        .map((e) => TraccarPosition.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<SummaryReport>> getSummary(
    int deviceId,
    String fromIso,
    String toIso,
  ) async {
    final decoded = await _authorizedGetJson(
      '/api/reports/summary?deviceId=$deviceId&from=${Uri.encodeQueryComponent(fromIso)}&to=${Uri.encodeQueryComponent(toIso)}',
      timeout: const Duration(seconds: 45),
    );
    if (decoded is! List) return <SummaryReport>[];
    return decoded
        .whereType<Map>()
        .map((e) => SummaryReport.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<TripReport>> getTrips(
    int deviceId,
    String fromIso,
    String toIso,
  ) async {
    final decoded = await _authorizedGetJson(
      '/api/reports/trips?deviceId=$deviceId&from=${Uri.encodeQueryComponent(fromIso)}&to=${Uri.encodeQueryComponent(toIso)}',
      timeout: const Duration(seconds: 45),
    );
    if (decoded is! List) return <TripReport>[];
    return decoded
        .whereType<Map>()
        .map((e) => TripReport.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<StopReportModel>> getStops(
    int deviceId,
    String fromIso,
    String toIso,
  ) async {
    final decoded = await _authorizedGetJson(
      '/api/reports/stops?deviceId=$deviceId&from=${Uri.encodeQueryComponent(fromIso)}&to=${Uri.encodeQueryComponent(toIso)}',
      timeout: const Duration(seconds: 45),
    );
    if (decoded is! List) return <StopReportModel>[];
    return decoded
        .whereType<Map>()
        .map((e) => StopReportModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<DeviceEventModel>> getEvents(
    int deviceId,
    String fromIso,
    String toIso,
  ) async {
    final decoded = await _authorizedGetJson(
      '/api/reports/events?deviceId=$deviceId&from=${Uri.encodeQueryComponent(fromIso)}&to=${Uri.encodeQueryComponent(toIso)}',
      timeout: const Duration(seconds: 45),
    );
    if (decoded is! List) return <DeviceEventModel>[];
    return decoded
        .whereType<Map>()
        .map((e) => DeviceEventModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<RoutePoint>> getRoute(
    int deviceId,
    String fromIso,
    String toIso,
  ) async {
    final decoded = await _authorizedGetJson(
      '/api/reports/route?deviceId=$deviceId&from=${Uri.encodeQueryComponent(fromIso)}&to=${Uri.encodeQueryComponent(toIso)}',
      timeout: const Duration(seconds: 45),
    );
    if (decoded is! List) return <RoutePoint>[];
    return decoded
        .whereType<Map>()
        .map((e) => RoutePoint.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> updatePassword(String newPassword) async {
    final user = await ensureSession();
    final payload = Map<String, dynamic>.from(user.rawJson);
    payload['password'] = newPassword;

    final uri = Uri.parse('$serverUrl/api/users/${user.id}');
    final request = await _httpClient!.openUrl('PUT', uri);
    request.headers.contentType = ContentType.json;
    final basicAuth =
        'Basic ${base64Encode(utf8.encode('$email:$password'))}';
    request.headers.set(HttpHeaders.authorizationHeader, basicAuth);
    final cookie = _cookieHeader;
    if (cookie != null) {
      request.headers.set(HttpHeaders.cookieHeader, cookie);
    }
    request.write(jsonEncode(payload));

    final response = await request.close().timeout(const Duration(seconds: 12));
    await response.drain<void>();
    if (response.statusCode != 200) {
      throw HttpException('Password update failed (${response.statusCode})');
    }
  }

  Future<void> fetchLatestPositions() async {
    final now = DateTime.now();
    if (_isFetchingPositions &&
        now.difference(_lastFetchTime).inSeconds < 10) {
      return;
    }
    _isFetchingPositions = true;
    _lastFetchTime = now;
    try {
      await getDevices();
      await getLastPositions();
      _lastFetchFailed = false;
      _emitLiveUpdate();
    } catch (e) {
      _lastFetchFailed = true;
      if (kDebugMode) {
        debugPrint('TraccarService.fetchLatestPositions error: $e');
      }
    } finally {
      _isFetchingPositions = false;
    }
  }

  void startRealtimeSync() {
    if (_isSyncActive) return;
    _isSyncActive = true;

    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final key = results.map((e) => e.name).toList()..sort();
        final joined = key.join(',');
        if (_lastConnectivityKey != null && _lastConnectivityKey != joined) {
          _lastConnectivityKey = joined;
          if (!results.contains(ConnectivityResult.none)) {
            handleNetworkSwitch();
          }
        } else {
          _lastConnectivityKey ??= joined;
        }
      },
    );

    _androidNetworkSub?.cancel();
    if (Platform.isAndroid) {
      _androidNetworkSub =
          _androidNetworkChannel.receiveBroadcastStream().listen(
        (dynamic event) {
          if (event is String &&
              (event.startsWith('available:') || event.startsWith('lost:'))) {
            handleNetworkSwitch();
          }
        },
        onError: (_) {},
      );
    }

    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        if (!_isSyncActive) return;
        await fetchLatestPositions();
        if (!_isSyncActive) return;
        if (_webSocket == null || _lastFetchFailed) {
          handleNetworkSwitch();
        }
      },
    );

    _connectWebSocket();
  }

  void stopRealtimeSync() {
    _isSyncActive = false;
    _connectSeq++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _androidNetworkSub?.cancel();
    _androidNetworkSub = null;
    _closeWebSocket();
  }

  void handleNetworkSwitch() {
    if (!_isSyncActive) return;
    _connectSeq++;
    evictConnections();
    _closeWebSocket();
    _isFetchingPositions = false;
    _scheduleReconnect(const Duration(milliseconds: 200));
  }

  void _closeWebSocket() {
    final ws = _webSocket;
    _webSocket = null;
    if (ws != null) {
      try {
        ws.close();
      } catch (_) {}
    }
  }

  void _scheduleReconnect(Duration delay) {
    if (!_isSyncActive) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connectWebSocket);
  }

  Future<void> _connectWebSocket() async {
    if (!_isSyncActive) return;
    final attemptId = ++_connectSeq;
    _closeWebSocket();

    try {
      await fetchLatestPositions();
      if (!_isSyncActive || attemptId != _connectSeq) return;
      if (_lastFetchFailed) {
        _scheduleReconnect(const Duration(seconds: 2));
        return;
      }

      final cookie = _cookieHeader;
      final base = Uri.parse(serverUrl);
      final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';
      final wsUri = base.replace(
        scheme: wsScheme,
        path: '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}/api/socket',
      );

      final headers = <String, dynamic>{};
      if (cookie != null) {
        headers[HttpHeaders.cookieHeader] = cookie;
      }

      final ws = await WebSocket.connect(wsUri.toString(), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (!_isSyncActive || attemptId != _connectSeq) {
        await ws.close();
        return;
      }

      ws.pingInterval = const Duration(seconds: 10);
      _webSocket = ws;

      ws.listen(
        (dynamic message) {
          if (ws != _webSocket) return;
          if (message is String) {
            _handleWsMessage(message);
          }
        },
        onError: (Object err) {
          if (ws != _webSocket) return;
          _webSocket = null;
          _scheduleReconnect(const Duration(seconds: 3));
        },
        onDone: () {
          if (ws != _webSocket) return;
          _webSocket = null;
          _scheduleReconnect(const Duration(seconds: 3));
        },
        cancelOnError: true,
      );
    } on UnauthorizedException {
      _sessionValid = false;
      if (attemptId == _connectSeq) {
        _scheduleReconnect(const Duration(seconds: 3));
      }
    } on WebSocketException catch (e) {
      _webSocket = null;
      if (e.message.contains('401') || e.message.contains('Unauthorized')) {
        _sessionValid = false;
      }
      if (attemptId == _connectSeq) {
        _scheduleReconnect(const Duration(seconds: 3));
      }
    } catch (_) {
      _webSocket = null;
      if (attemptId == _connectSeq) {
        _scheduleReconnect(const Duration(seconds: 3));
      }
    }
  }

  void _handleWsMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final rawDevices = decoded['devices'];
      if (rawDevices is List) {
        for (final item in rawDevices) {
          if (item is Map) {
            final dev = TraccarDevice.fromJson(Map<String, dynamic>.from(item));
            devices[dev.id] = dev;
          }
        }
      }

      final rawPositions = decoded['positions'];
      if (rawPositions is List) {
        final parsedPositions = <TraccarPosition>[];
        for (final item in rawPositions) {
          if (item is Map) {
            parsedPositions.add(
              TraccarPosition.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
        parsedPositions.sort((a, b) {
          final ta = a.fixTime;
          final tb = b.fixTime;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return ta.compareTo(tb);
        });
        for (final pos in parsedPositions) {
          ingestPosition(pos);
        }
      }
      _emitLiveUpdate();
    } catch (_) {
      // Ignore malformed WebSocket messages.
    }
  }

  void _emitLiveUpdate() {
    if (!_updateController.isClosed) {
      _updateController.add(null);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    stopRealtimeSync();
    await _prefs?.setBool(prefAuthenticated, false);
    await _prefs?.remove(prefPassword);
    resetSession();
    devices.clear();
    positions.clear();
    _positionObservedAt.clear();
    motionTracker.clear();
    evictConnections();
  }
}
