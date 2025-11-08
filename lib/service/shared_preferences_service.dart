import 'dart:convert';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesService extends GetxService {
  static SharedPreferences? _sharedPreferences;

  SharedPreferences get instance => _sharedPreferences!;

  static String keyHomeIndex = 'home_index';
  static String keyPhoneCallUserAgreement = 'phone_call_user_agreement';
  static String keyGeoTrackingConsent = 'geo_tracking_consent';
  static String keyGeoTrackingSegments = 'geo_tracking_segments';
  static String keyGeoTrackingConfig = 'geo_tracking_config';

  static const int _defaultGeoTrackingSegmentLimit = 20;

  Future<SharedPreferencesService> init() async {
    await SharedPreferences.getInstance().then(
      (value) => _sharedPreferences = value,
    );
    return this;
  }

  bool getGeoTrackingConsent() {
    return instance.getBool(keyGeoTrackingConsent) ?? false;
  }

  Future<void> setGeoTrackingConsent(bool value) async {
    await instance.setBool(keyGeoTrackingConsent, value);
  }

  List<Map<String, dynamic>> getGeoTrackingSegments() {
    final List<String> rawList = instance.getStringList(keyGeoTrackingSegments) ?? <String>[];
    return rawList
        .map((entry) {
          try {
            final Object? decoded = jsonDecode(entry);
            if (decoded is Map<String, dynamic>) {
              return decoded;
            }
          } catch (_) {
            // ignore malformed entry
          }
          return <String, dynamic>{};
        })
        .where((element) => element.isNotEmpty)
        .toList();
  }

  Future<void> appendGeoTrackingSegment(Map<String, dynamic> segment, {int? maxSegments}) async {
    final int limit = maxSegments ?? _defaultGeoTrackingSegmentLimit;
    final List<String> rawList = instance.getStringList(keyGeoTrackingSegments) ?? <String>[];
    rawList.add(jsonEncode(segment));

    if (rawList.length > limit) {
      rawList.removeRange(0, rawList.length - limit);
    }

    await instance.setStringList(keyGeoTrackingSegments, rawList);
  }

  Future<void> clearGeoTrackingSegments() async {
    await instance.remove(keyGeoTrackingSegments);
  }

  Map<String, dynamic>? getGeoTrackingConfig() {
    final String? rawJson = instance.getString(keyGeoTrackingConfig);
    if (rawJson == null) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      // ignore malformed entry
    }
    return null;
  }

  Future<void> setGeoTrackingConfig(Map<String, dynamic> config) async {
    await instance.setString(keyGeoTrackingConfig, jsonEncode(config));
  }
}
