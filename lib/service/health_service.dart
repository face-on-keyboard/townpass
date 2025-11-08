import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:health/health.dart';

class HealthSnapshot {
  final int steps;
  final double distanceMeters;
  final DateTime intervalStart;
  final DateTime intervalEnd;

  const HealthSnapshot({
    required this.steps,
    required this.distanceMeters,
    required this.intervalStart,
    required this.intervalEnd,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'steps': steps,
      'distance_meters': distanceMeters,
      'start_time': intervalStart.toUtc().toIso8601String(),
      'end_time': intervalEnd.toUtc().toIso8601String(),
    };
  }
}

class HealthException implements Exception {
  final String message;

  HealthException(this.message);

  @override
  String toString() => 'HealthException: $message';
}

class HealthService extends GetxService {
  Health? _health;

  static const List<HealthDataType> _dataTypes = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_WALKING_RUNNING,
  ];

  Future<HealthService> init() async {
    if (kIsWeb) {
      return this;
    }

    if (Platform.isIOS || Platform.isAndroid) {
      _health = Health();
      await _health!.configure();
    }
    return this;
  }

  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<bool> _ensureAuthorized() async {
    if (!isSupportedPlatform || _health == null) {
      return false;
    }

    final List<HealthDataAccess> permissions =
        List<HealthDataAccess>.filled(_dataTypes.length, HealthDataAccess.READ);

    bool hasPermissions =
        await _health!.hasPermissions(_dataTypes, permissions: permissions) ?? false;

    if (!hasPermissions) {
      hasPermissions =
          await _health!.requestAuthorization(_dataTypes, permissions: permissions);
    }

    return hasPermissions;
  }

  Future<HealthSnapshot> fetchTodaySummary() async {
    final DateTime now = DateTime.now();
    final DateTime start = DateTime(now.year, now.month, now.day);

    if (!await _ensureAuthorized()) {
      throw HealthException('Health permission not granted');
    }

    int steps = 0;
    double distanceMeters = 0.0;

    try {
      final int? totalSteps = await _health!.getTotalStepsInInterval(start, now);
      steps = totalSteps ?? 0;
    } catch (error, stackTrace) {
      debugPrint('HealthService#getTotalStepsInInterval error: $error\n$stackTrace');
      steps = 0;
    }

    try {
      final List<HealthDataPoint> points = await _health!
          .getHealthDataFromTypes(types: <HealthDataType>[HealthDataType.DISTANCE_WALKING_RUNNING], startTime: start, endTime: now);
      final Set<String> seen = {};
      final Iterable<HealthDataPoint> deduplicated = points.where((p) {
        final id = '${p.type}-${p.dateFrom.toIso8601String()}-${p.dateTo.toIso8601String()}';
        return seen.add(id);
      });
      distanceMeters = deduplicated.fold<double>(
        0.0,
        (double previousValue, HealthDataPoint element) {
          final dynamic value = element.value;
          if (value is num) {
            return previousValue + value.toDouble();
          }
          return previousValue;
        },
      );
    } catch (error, stackTrace) {
      debugPrint('HealthService#getHealthDataFromTypes error: $error\n$stackTrace');
      distanceMeters = 0.0;
    }

    return HealthSnapshot(
      steps: steps,
      distanceMeters: distanceMeters,
      intervalStart: start,
      intervalEnd: now,
    );
  }
}

