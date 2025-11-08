# Health Data Integration Setup

This feature reads the user’s activity metrics (steps, walking/running distance) for the current day and exposes them to the Face on Keyboard web view. The Flutter code now relies on the [`health`](https://pub.dev/packages/health) package, which bridges to Apple HealthKit and Google Fit. Follow the steps below before running on physical devices.

## iOS – HealthKit

1. **Enable the HealthKit capability**
   - Open `ios/Runner.xcworkspace` in Xcode.
   - Select the `Runner` target → **Signing & Capabilities** → press “+ Capability” → add **HealthKit**.
   - Xcode will update the signing entitlements to reference `Runner/Runner.entitlements`. The repository already contains this file with `com.apple.developer.healthkit = true`.

2. **Usage descriptions**
   - `ios/Runner/Info.plist` now declares `NSHealthShareUsageDescription`. Confirm the text matches your privacy messaging.

3. **Runtime authorisation**
   - The Flutter `HealthService` requests read access to:
     - `HKQuantityTypeIdentifier.stepCount`
     - `HKQuantityTypeIdentifier.distanceWalkingRunning`
   - The system permission sheet must be accepted on device; otherwise we return an error payload to the web view.

4. **Developer account requirements**
   - HealthKit only works on real hardware signed with a developer certificate & provisioning profile that includes the HealthKit capability.
   - Ensure the demo device has the user’s Health data available (or add mock data via the Health app).

## Android – Google Fit

1. **Update Google Cloud credentials**
   - Create an OAuth 2.0 client ID for your Android app in Google Cloud Console.
   - Use the application id `com.example.townpass` (or your final id) plus the SHA‑1 / SHA‑256 fingerprints.
   - Enable the **Fitness API** for the same project.
   - Download the `google-services.json` / OAuth credentials and configure them according to Google Fit + `health` package documentation.

2. **Permissions**
   - `android/app/src/main/AndroidManifest.xml` now requests:
     - `android.permission.ACTIVITY_RECOGNITION`
     - `com.google.android.gms.permission.ACTIVITY_RECOGNITION`
   - At runtime Android 10+ will prompt for Activity Recognition access when we first query Google Fit.

3. **Dependencies**
   - `android/app/build.gradle` pulls `com.google.android.gms:play-services-fitness` and `play-services-auth`, and raises `minSdkVersion` to at least 23.

## Web message contract

The Face on Keyboard web view can include the following when posting to `face_on_keyboard_location`:

```json
{
  "name": "face_on_keyboard_location",
  "data": {
    "request_health": true
  }
}
```

If `request_health` is `true`, the app replies with:

```json
{
  "segments": [...],
  "config": {...},
  "health": {
    "steps": 1234,
    "distance_meters": 456.7,
    "start_time": "2025-11-08T00:00:00Z",
    "end_time": "2025-11-08T08:15:30Z"
  }
}
```

If HealthKit / Google Fit permissions are missing or the platform is unsupported, the `health` field contains an error object describing the failure so the web layer can react accordingly.

