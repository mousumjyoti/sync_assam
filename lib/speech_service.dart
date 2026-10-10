import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'settings.dart';

class SpeechException implements Exception {
  SpeechException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef ProgressCallback = void Function(String message);

class SpeechService {
  SpeechService(this.settings, this.client);

  final AppSettings settings;
  final http.Client client;

  static const _inlineMaxBytes = 4 * 1024 * 1024;
  static const _inlineMaxSeconds = 55.0;

  static String hostForLocation(String location) =>
      location == 'global'
          ? 'speech.googleapis.com'
          : '$location-speech.googleapis.com';

  String get _speechHost => hostForLocation(settings.location);

  bool useInline(List<int> bytes, double? durationSeconds) {
    if (bytes.length > _inlineMaxBytes) return false;
    if (durationSeconds != null) return durationSeconds < _inlineMaxSeconds;
    return true;
  }

  Future<List<WordToken>> transcribe({
    required List<int> bytes,
    required String languageCode,
    required String fileExtension,
    double? durationSeconds,
    ProgressCallback? onProgress,
  }) async {
    final projectId = settings.projectId;
    if (projectId == null) {
      throw SpeechException('Could not read project_id from the service account JSON.');
    }

    if (useInline(bytes, durationSeconds)) {
      onProgress?.call('Transcribing inline (sync recognize)...');
      try {
        return await _recognizeInline(projectId, bytes, languageCode);
      } on SpeechException catch (e) {
        final tooLong = e.message.toLowerCase().contains('60') ||
            e.message.toLowerCase().contains('too long');
        if (!tooLong || !settings.hasBucket) rethrow;
        onProgress?.call(
            'Audio was too long for inline mode, switching to batch...');
      }
    } else if (!settings.hasBucket) {
      throw SpeechException(
        'Audio is too long for inline recognition. Set a Cloud Storage '
        'bucket in Settings to transcribe long files.',
      );
    }
    onProgress?.call('Uploading audio to Cloud Storage...');
    final uri = await _uploadToBucket(bytes, fileExtension);
    try {
      onProgress?.call('Starting batch recognition...');
      final tokens = await _batchRecognize(projectId, uri, languageCode, onProgress);
      await _deleteUploadedObject(uri);
      return tokens;
    } catch (e) {
      await _deleteUploadedObject(uri);
      rethrow;
    }
  }

  Map<String, dynamic> _recognitionConfig(String languageCode) => {
        'model': 'chirp_2',
        'autoDecodingConfig': {},
        'languageCodes': [languageCode],
        'features': {
          'enableWordTimeOffsets': true,
          'enableAutomaticPunctuation': true,
        },
      };

  Future<List<WordToken>> _recognizeInline(
    String projectId,
    List<int> bytes,
    String languageCode,
  ) async {
    final url = Uri.https(
      _speechHost,
      '/v2/projects/$projectId/locations/${settings.location}/recognizers/_:recognize',
    );
    final body = {
      'config': _recognitionConfig(languageCode),
      'configMask': '*',
      'content': base64Encode(bytes),
    };
    final resp = await client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final json = _decodeOrThrow(resp, 'recognize');
    return _wordsFromResults(json['results']);
  }

  Future<String> _uploadToBucket(List<int> bytes, String ext) async {
    final objectName =
        'sync_assam/audio_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final boundary = 'boundary_${Random().nextInt(1 << 30)}';
    final metadata = jsonEncode({'name': objectName});
    final body = <int>[
      ...utf8.encode('--$boundary\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '$metadata\r\n'),
      ...utf8.encode('--$boundary\r\n'
          'Content-Type: ${_mimeFor(ext)}\r\n\r\n'),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    final url = Uri.https(
      'storage.googleapis.com',
      '/upload/storage/v1/b/${settings.bucket}/o',
      {'uploadType': 'multipart'},
    );
    try {
      final resp = await client.post(
        url,
        headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
        body: body,
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _decodeOrThrow(resp, 'Cloud Storage upload');
      }
    } on SpeechException {
      rethrow;
    } catch (e) {
      throw SpeechException(
        'Cloud Storage upload failed: $e\n'
        'Check that bucket "${settings.bucket}" exists and the service '
        'account has Storage Object Admin on it.',
      );
    }
    return 'gs://${settings.bucket}/$objectName';
  }

  Future<void> _deleteUploadedObject(String gsUri) async {
    try {
      final rest = gsUri.substring('gs://'.length);
      final slash = rest.indexOf('/');
      final bucket = rest.substring(0, slash);
      final name = rest.substring(slash + 1);
      await client.delete(
        Uri.https('storage.googleapis.com', '/storage/v1/b/$bucket/o/$name'),
      );
    } catch (_) {
      // best effort cleanup
    }
  }

  Future<List<WordToken>> _batchRecognize(
    String projectId,
    String gsUri,
    String languageCode,
    ProgressCallback? onProgress,
  ) async {
    final url = Uri.https(
      _speechHost,
      '/v2/projects/$projectId/locations/${settings.location}/recognizers/_:batchRecognize',
    );
    final body = {
      'config': _recognitionConfig(languageCode),
      'configMask': '*',
      'files': [
        {'uri': gsUri},
      ],
      'recognitionOutputConfig': {
        'inlineResponseConfig': {},
      },
    };
    final resp = await client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final operation = _decodeOrThrow(resp, 'batchRecognize');
    final name = operation['name'];
    if (name is! String) {
      throw SpeechException('batchRecognize returned no operation name.');
    }

    final deadline = DateTime.now().add(const Duration(minutes: 30));
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw SpeechException('Timed out after 30 minutes waiting for recognition.');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      final poll = await client.get(
        Uri.https(_speechHost, '/v2/$name'),
      );
      final op = _decodeOrThrow(poll, 'operations.get');
      final metadata = op['metadata'];
      if (metadata is Map<String, dynamic>) {
        final progress = metadata['progressPercent'];
        if (progress is int && progress < 100) {
          onProgress?.call('Recognizing... $progress%');
        }
      }
      if (op['done'] == true) {
        if (op['error'] != null) {
          final err = op['error'];
          final msg = err is Map ? (err['message'] ?? jsonEncode(err)) : '$err';
          throw SpeechException('Recognition failed: $msg');
        }
        final response = op['response'];
        if (response is! Map<String, dynamic>) {
          throw SpeechException('Operation completed with no response.');
        }
        final results = response['results'];
        final inline = (results is List &&
                results.isNotEmpty &&
                results.first is Map<String, dynamic>)
            ? (results.first as Map<String, dynamic>)['inlineResult']
            : null;
        if (inline is! Map<String, dynamic>) {
          throw SpeechException('No inline result in batch response.');
        }
        onProgress?.call('Recognition finished.');
        return _wordsFromResults(inline['results']);
      }
    }
  }

  List<WordToken> _wordsFromResults(dynamic results) {
    final tokens = <WordToken>[];
    if (results is! List) return tokens;
    for (final r in results) {
      if (r is! Map) continue;
      final alternatives = r['alternatives'];
      if (alternatives is! List || alternatives.isEmpty) continue;
      final top = alternatives.first;
      if (top is! Map) continue;
      final words = top['words'];
      if (words is! List) continue;
      for (final w in words) {
        if (w is! Map) continue;
        final word = w['word'];
        if (word is! String) continue;
        final start = w['startOffset'] is String
            ? parseOffsetSeconds(w['startOffset'] as String)
            : 0.0;
        final end = w['endOffset'] is String
            ? parseOffsetSeconds(w['endOffset'] as String)
            : 0.0;
        tokens.add(WordToken(word: word, start: start, end: end));
      }
    }
    return tokens;
  }

  Map<String, dynamic> _decodeOrThrow(http.Response resp, String api) {
    Map<String, dynamic>? parsed;
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) parsed = decoded;
    } catch (_) {}

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (parsed == null) {
        throw SpeechException('$api returned unreadable JSON.');
      }
      return parsed;
    }

    final message = (parsed != null &&
            parsed['error'] is Map &&
            (parsed['error'] as Map)['message'] is String)
        ? (parsed['error'] as Map)['message'] as String
        : resp.body;

    switch (resp.statusCode) {
      case 401:
        throw SpeechException(
          'Authentication failed (401): the service account credentials were '
          'rejected. Check the pasted JSON.',
        );
      case 403:
        final pid = settings.projectId ?? 'the project in the URL';
        final email = settings.serviceAccountEmail ?? 'the pasted JSON';
        throw SpeechException(
          'Permission denied (403) for project "$pid". Fix in Google Cloud '
          'Console, with the project switcher set to that project: '
          '(1) APIs & Services → enable "Cloud Speech-to-Text API"; '
          '(2) IAM & Admin → grant "$email" role "Cloud Speech Client" '
          '(roles/speech.client, or Editor/Administrator) at project level — '
          '"Cloud Speech-to-Text API User" does not exist; '
          '(3) confirm the billing account attached to the project is '
          'active. ($message)',
        );
      case 400:
        throw SpeechException(
          'Bad request (400): language, location, or audio format not '
          'accepted ($message).',
        );
      default:
        throw SpeechException('$api failed with HTTP ${resp.statusCode}: $message');
    }
  }

  static String _mimeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      case 'amr':
        return 'audio/amr';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }
}
