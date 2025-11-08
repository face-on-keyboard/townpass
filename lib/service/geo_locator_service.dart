import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:town_pass/service/notification_service.dart';
import 'package:town_pass/service/shared_preferences_service.dart';

class GeoLocatorService extends GetxService {
  final SharedPreferencesService _preferencesService = SharedPreferencesService();

  GeoTrackingConfig _config = const GeoTrackingConfig.defaults();

  StreamSubscription<Position>? _positionSubscription;
  Position? _segmentStartPosition;
  DateTime? _segmentStartTime;
  double? _lastSpeed;

  GeoTrackingConfig get currentConfig => _config;

  Future<GeoLocatorService> init() async {
    _loadStoredConfig();
    _log('Initial config loaded: $_config');

    if (_preferencesService.getGeoTrackingConsent()) {
      _log('Geo tracking consent found. Starting background tracking.');
      await _startBackgroundTracking();
    }
    return this;
  }

  @override
  void onClose() {
    _positionSubscription?.cancel();
    super.onClose();
  }

  Future<Position> position() async {
    await _ensurePermissionGranted();
    return Geolocator.getCurrentPosition();
  }

  Future<bool> ensureTrackingIfRequired({required bool requiresTracking}) async {
    if (!requiresTracking) {
      return true;
    }

    try {
      return await ensureBackgroundTrackingEnabled();
    } catch (error) {
      Get.snackbar(
        '定位失敗',
        error.toString(),
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
      return false;
    }
  }

  Future<bool> ensureBackgroundTrackingEnabled() async {
    if (_preferencesService.getGeoTrackingConsent()) {
      try {
        await _ensurePermissionGranted();
      } catch (error) {
        await _preferencesService.setGeoTrackingConsent(false);
        rethrow;
      }
      _log('Background tracking already consented. Ensuring stream is running.');
      await _startBackgroundTracking();
      return true;
    }

    final bool consent = await _showConsentDialog();
    if (!consent) {
      await _preferencesService.setGeoTrackingConsent(false);
      await _stopBackgroundTracking();
      _log('User declined background tracking.');
      return false;
    }

    try {
      await _ensurePermissionGranted();
    } catch (error) {
      await _preferencesService.setGeoTrackingConsent(false);
      rethrow;
    }
    await _preferencesService.setGeoTrackingConsent(true);
    _log('User granted background tracking consent.');
    await _startBackgroundTracking();
    return true;
  }

  Future<List<Map<String, dynamic>>> loadTrackedSegments() async {
    final List<Map<String, dynamic>> segments = _preferencesService
        .getGeoTrackingSegments()
        .map((segment) {
          try {
            return GeoTrackSegment.fromJson(segment).toJson();
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((element) => element.isNotEmpty)
        .toList();
    _log('Loaded ${segments.length} stored geo segments.');
    return segments;
  }

  Future<void> clearTrackedSegments() async {
    await _preferencesService.clearGeoTrackingSegments();
    _log('Cleared stored geo segments upon request.');
  }
  
  Future<void> clearTrackingConfig() async {
    await _preferencesService.clearGeoTrackingConfig();
    _log('Cleared stored geo tracking config.');
  }

  Future<void> _startBackgroundTracking() async {
    if (_positionSubscription != null) {
      _log('Background tracking already running. Skipping start.');
      return;
    }

    _segmentStartPosition = null;
    _segmentStartTime = null;
    _lastSpeed = null;

    _log('Starting background tracking with config: $_config');

    _positionSubscription = Geolocator.getPositionStream(locationSettings: _buildLocationSettings()).listen(
      (Position position) async {
        _log('Received position update: (${position.latitude}, ${position.longitude}), speed=${position.speed} m/s.');
        await _handlePositionUpdate(position);
      },
      onError: (Object error, StackTrace stackTrace) {
        printError(info: 'GeoLocatorService stream error: $error');
      },
    );

    try {
      final Position initialPosition = await Geolocator.getCurrentPosition();
      _segmentStartPosition = initialPosition;
      _segmentStartTime = initialPosition.timestamp;
      _updateSpeed(initialPosition.speed);
    } catch (error) {
      printError(info: 'GeoLocatorService failed to seed initial position: $error');
    }
  }

  Future<void> _stopBackgroundTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _segmentStartPosition = null;
    _segmentStartTime = null;
    _lastSpeed = null;
    _log('Background tracking stopped.');
  }

  Future<void> _handlePositionUpdate(Position position) async {
    final DateTime now = position.timestamp;

    if (_segmentStartPosition == null || _segmentStartTime == null) {
      _segmentStartPosition = position;
      _segmentStartTime = now;
      _updateSpeed(position.speed);
      return;
    }

    final bool durationExceeded = now.difference(_segmentStartTime!).abs() >= _config.segmentDurationThreshold;
    final bool speedChanged = _hasSpeedChanged(position.speed);

    if (!durationExceeded && !speedChanged) {
      _updateSpeed(position.speed);
      return;
    }

    final GeoTrackSegment segment = GeoTrackSegment(
      startLongitude: _segmentStartPosition!.longitude,
      startLatitude: _segmentStartPosition!.latitude,
      startTime: _segmentStartTime!,
      endLongitude: position.longitude,
      endLatitude: position.latitude,
      endTime: now,
    );

    await _storeSegment(segment);

    _segmentStartPosition = position;
    _segmentStartTime = now;
    _updateSpeed(position.speed);
  }

  Future<void> _storeSegment(GeoTrackSegment segment) async {
    await _preferencesService.appendGeoTrackingSegment(segment.toJson());
    _log('Stored segment: ${segment.summary}');
    await NotificationService.showNotification(
      title: '定位紀錄已更新',
      content: '時間 ${segment.startTime.toLocal().toIso8601String()} 至 ${segment.endTime.toLocal().toIso8601String()}',
    );
  }

  Future<void> _ensurePermissionGranted() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw '未開啟定位服務';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw '使用者未允許定位權限';
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw '使用者未允許定位權限（永久），無法取得定位資訊';
    }
  }

  Future<void> updateTrackingConfig({
    Duration? segmentDuration,
    double? speedThreshold,
    int? distanceFilter,
  }) async {
    final GeoTrackingConfig originalConfig = _config;
    _config = _config.copyWith(
      segmentDurationThreshold: segmentDuration,
      speedChangeThreshold: speedThreshold,
      distanceFilterMeters: distanceFilter,
    );
    await _preferencesService.setGeoTrackingConfig(_config.toStorageJson());
    _log('Updated tracking config from $originalConfig to $_config');

    if (_positionSubscription != null) {
      _log('Restarting background stream to apply new config.');
      await _stopBackgroundTracking();
      await _startBackgroundTracking();
    }
  }

  Future<void> logDebugState({bool includeSegments = false}) async {
    _log('--- Geo tracking debug info ---');
    _log('Consent: ${_preferencesService.getGeoTrackingConsent()}');
    _log('Tracking active: ${_positionSubscription != null}');
    _log('Current config: $_config');
    _log('Current segment start: ${_segmentStartPosition == null ? 'none' : '${_segmentStartPosition!.latitude}, ${_segmentStartPosition!.longitude} at $_segmentStartTime'}');
    if (includeSegments) {
      final List<Map<String, dynamic>> segments = await loadTrackedSegments();
      _log('Stored segments (${segments.length}):');
      for (final Map<String, dynamic> map in segments) {
        try {
          final GeoTrackSegment segment = GeoTrackSegment.fromJson(map);
          _log('  - ${segment.summary}');
        } catch (_) {
          _log('  - (malformed segment): $map');
        }
      }
    }
    _log('--- End geo tracking debug info ---');
  }

  void _loadStoredConfig() {
    final Map<String, dynamic>? storedMap = _preferencesService.getGeoTrackingConfig();
    if (storedMap == null) {
      _config = const GeoTrackingConfig.defaults();
      return;
    }

    try {
      _config = GeoTrackingConfig.fromStorageJson(storedMap);
    } catch (error) {
      _log('Failed to parse stored geo tracking config ($error). Falling back to defaults.');
      _config = const GeoTrackingConfig.defaults();
    }
  }

  LocationSettings _buildLocationSettings() {
    return LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: _config.distanceFilterMeters,
    );
  }

  Future<bool> _showConsentDialog() async {
    final bool? result = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('啟用背景定位？'),
        content: const Text('將於背景取得位置資訊並於行程變化時通知您，確認要啟用嗎？'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('同意'),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    return result ?? false;
  }

  bool _hasSpeedChanged(double speed) {
    if (speed < 0) {
      return false;
    }
    if (_lastSpeed == null) {
      return false;
    }
    return (speed - _lastSpeed!).abs() >= _config.speedChangeThreshold;
  }

  void _updateSpeed(double speed) {
    if (speed >= 0) {
      _lastSpeed = speed;
    }
  }

  void _log(String message) {
    debugPrint('[GeoLocatorService] $message');
  }
}

class GeoTrackSegment {
  final double startLongitude;
  final double startLatitude;
  final DateTime startTime;
  final double endLongitude;
  final double endLatitude;
  final DateTime endTime;

  GeoTrackSegment({
    required this.startLongitude,
    required this.startLatitude,
    required this.startTime,
    required this.endLongitude,
    required this.endLatitude,
    required this.endTime,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'start_x': startLongitude,
      'start_y': startLatitude,
      'start_time': startTime.toUtc().toIso8601String(),
      'end_x': endLongitude,
      'end_y': endLatitude,
      'end_time': endTime.toUtc().toIso8601String(),
    };
  }

  factory GeoTrackSegment.fromJson(Map<String, dynamic> json) {
    return GeoTrackSegment(
      startLongitude: (json['start_x'] as num).toDouble(),
      startLatitude: (json['start_y'] as num).toDouble(),
      startTime: DateTime.parse(json['start_time'] as String).toLocal(),
      endLongitude: (json['end_x'] as num).toDouble(),
      endLatitude: (json['end_y'] as num).toDouble(),
      endTime: DateTime.parse(json['end_time'] as String).toLocal(),
    );
  }

  String get summary {
    final Duration duration = endTime.difference(startTime);
    return 'from ($startLatitude, $startLongitude) at ${startTime.toLocal().toIso8601String()} '
        'to ($endLatitude, $endLongitude) at ${endTime.toLocal().toIso8601String()} (duration ${duration.inSeconds}s)';
  }
}

class GeoTrackingConfig {
  final Duration segmentDurationThreshold;
  final double speedChangeThreshold;
  final int distanceFilterMeters;

  const GeoTrackingConfig({
    required this.segmentDurationThreshold,
    required this.speedChangeThreshold,
    required this.distanceFilterMeters,
  });

  const GeoTrackingConfig.defaults()
      : segmentDurationThreshold = const Duration(seconds: 10),
        speedChangeThreshold = 0.0,
        distanceFilterMeters = 0;

  GeoTrackingConfig copyWith({
    Duration? segmentDurationThreshold,
    double? speedChangeThreshold,
    int? distanceFilterMeters,
  }) {
    return GeoTrackingConfig(
      segmentDurationThreshold: segmentDurationThreshold ?? this.segmentDurationThreshold,
      speedChangeThreshold: speedChangeThreshold ?? this.speedChangeThreshold,
      distanceFilterMeters: distanceFilterMeters ?? this.distanceFilterMeters,
    );
  }

  Map<String, dynamic> toStorageJson() {
    final int sanitizedDuration = segmentDurationThreshold.inSeconds > 0 ? segmentDurationThreshold.inSeconds : const Duration(seconds: 10).inSeconds;
    final double sanitizedSpeed = speedChangeThreshold >= 0 ? speedChangeThreshold : 0.0;
    final int sanitizedDistance = distanceFilterMeters >= 0 ? distanceFilterMeters : 0;

    return <String, dynamic>{
      'segment_duration_seconds': sanitizedDuration,
      'speed_change_threshold_mps': sanitizedSpeed,
      'distance_filter_meters': sanitizedDistance,
    };
  }

  factory GeoTrackingConfig.fromStorageJson(Map<String, dynamic> json) {
    final int? segmentSeconds = (json['segment_duration_seconds'] as num?)?.toInt();
    final double? speedThreshold = (json['speed_change_threshold_mps'] as num?)?.toDouble();
    final int? distanceFilter = (json['distance_filter_meters'] as num?)?.toInt();

    final Duration segmentDuration = segmentSeconds != null ? Duration(seconds: segmentSeconds) : const Duration(seconds: 10);
    final double speed = speedThreshold ?? 0.0;
    final int distance = distanceFilter ?? 0;

    return GeoTrackingConfig(
      segmentDurationThreshold: segmentDuration,
      speedChangeThreshold: speed,
      distanceFilterMeters: distance,
    );
  }

  @override
  String toString() {
    return 'GeoTrackingConfig(duration=${segmentDurationThreshold.inSeconds}s, speedThreshold=${speedChangeThreshold.toStringAsFixed(2)}m/s, distanceFilter=${distanceFilterMeters}m)';
  }
}
