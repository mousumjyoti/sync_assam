import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const kScopeCloudPlatform = 'https://www.googleapis.com/auth/cloud-platform';

const kLocationChoices = <String>[
  'global',
  'us-central1',
  'us',
  'us-east1',
  'us-west1',
  'eu',
  'europe-west1',
  'europe-west4',
  'asia-southeast1',
  'asia-east1',
];

class AppSettings {
  const AppSettings({
    this.serviceAccountJson = '',
    this.location = 'us-central1',
    this.bucket = '',
    this.autoDetectLanguage = false,
  });

  final String serviceAccountJson;
  final String location;
  final String bucket;
  final bool autoDetectLanguage;

  bool get hasCredentials => serviceAccountJson.trim().isNotEmpty;
  bool get hasBucket => bucket.trim().isNotEmpty;

  Map<String, dynamic>? get _saMap {
    if (!hasCredentials) return null;
    try {
      final map = jsonDecode(serviceAccountJson);
      return map is Map<String, dynamic> ? map : null;
    } catch (_) {
      return null;
    }
  }

  /// V2 resource paths accept the project ID or the project number.
  String? get projectId {
    final map = _saMap;
    if (map == null) return null;
    for (final key in ['project_id', 'project_number']) {
      final value = map[key];
      final str = value is String
          ? value
          : value is num
              ? value.toString()
              : null;
      if (str != null && str.isNotEmpty) return str;
    }
    return null;
  }

  String? get serviceAccountEmail {
    final email = _saMap?['client_email'];
    return email is String && email.isNotEmpty ? email : null;
  }

  String? validate() {
    if (!hasCredentials) return 'Paste your service account JSON in Settings.';
    try {
      final map = jsonDecode(serviceAccountJson) as Map<String, dynamic>;
      for (final key in ['client_email', 'private_key', 'token_uri']) {
        if (map[key] is! String || (map[key] as String).isEmpty) {
          return 'Service account JSON is missing "$key". Paste the full file.';
        }
      }
      if (projectId == null) {
        return 'Service account JSON is missing "project_id".';
      }
    } catch (_) {
      return 'Service account JSON could not be parsed. Paste the complete file.';
    }
    return null;
  }

  Future<AuthClient> authClient() async {
    final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
    return clientViaServiceAccount(credentials, [kScopeCloudPlatform]);
  }
}

class SettingsStore {
  static const _keyJson = 'sa_json';
  static const _keyLocation = 'location';
  static const _keyBucket = 'bucket';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      serviceAccountJson: prefs.getString(_keyJson) ?? '',
      location: prefs.getString(_keyLocation) ?? 'us-central1',
      bucket: prefs.getString(_keyBucket) ?? '',
    );
  }

  static Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyJson, s.serviceAccountJson.trim());
    await prefs.setString(_keyLocation, s.location);
    await prefs.setString(_keyBucket, s.bucket.trim());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyJson);
    await prefs.remove(_keyLocation);
    await prefs.remove(_keyBucket);
  }
}

http.Client plainHttpClient() => http.Client();
