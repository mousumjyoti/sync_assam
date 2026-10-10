import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';
import '../settings.dart';
import '../speech_service.dart';
import 'preview_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _audioExtensions = [
    'mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac', 'amr', 'mp4', 'webm',
  ];

  AppSettings _settings = const AppSettings();
  File? _audioFile;
  String _language = 'as-IN';
  int _wordsPerLine = 2;
  bool _busy = false;
  String _progress = '';

  @override
  void initState() {
    super.initState();
    SettingsStore.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _audioExtensions,
      withData: false,
    );
    final path = result?.files.first.path;
    if (path != null) {
      setState(() => _audioFile = File(path));
    }
  }

  Future<double?> _probeDuration(String path) async {
    try {
      final player = AudioPlayer();
      try {
        final dur = await player.setFilePath(path);
        final ms = dur?.inMilliseconds;
        return ms == null ? null : ms / 1000.0;
      } finally {
        await player.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _generate() async {
    final file = _audioFile;
    if (file == null) {
      _toast('Pick an audio file first.');
      return;
    }
    final error = _settings.validate();
    if (error != null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Setup needed'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
      }
      return;
    }

    setState(() {
      _busy = true;
      _progress = 'Reading audio file...';
    });

    final authClient = await _settings.authClient();
    try {
      final service = SpeechService(_settings, authClient);
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      final duration = await _probeDuration(file.path);

      final tokens = await service.transcribe(
        bytes: bytes,
        languageCode: _language,
        fileExtension: ext,
        durationSeconds: duration,
        onProgress: (msg) {
          if (mounted) setState(() => _progress = msg);
        },
      );

      if (!mounted) return;
      if (tokens.isEmpty) {
        _toast('No speech was recognized in this audio.');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewPage(
            audioPath: file.path,
            tokens: tokens,
            wordsPerLine: _wordsPerLine,
          ),
        ),
      );
    } on SpeechException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Unexpected error: $e');
    } finally {
      authClient.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SRT Sync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              final updated = await Navigator.push<AppSettings>(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
              if (updated != null && mounted) {
                setState(() => _settings = updated);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  _settings.hasCredentials ? Icons.verified : Icons.warning_amber,
                  color: _settings.hasCredentials
                      ? Colors.green
                      : scheme.error,
                ),
                title: Text(
                  _settings.hasCredentials
                      ? 'Google credentials configured'
                      : 'Paste service account JSON in Settings',
                ),
                subtitle: _settings.hasCredentials
                    ? Text('Project: ${_settings.projectId ?? '?'}')
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final updated = await Navigator.push<AppSettings>(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                  if (updated != null && mounted) {
                    setState(() => _settings = updated);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1. Audio file',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickFile,
                      icon: const Icon(Icons.audiotrack),
                      label: Text(
                        _audioFile == null
                            ? 'Choose audio file'
                            : _shortName(_audioFile!.path),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_audioFile != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${(_audioFile!.lengthSync() / (1024 * 1024)).toStringAsFixed(1)} MB',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('2. Language',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _language,
                      items: kSupportedLanguages
                          .map(
                            (l) => DropdownMenuItem(
                              value: l.code,
                              child: Text(l.label),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _language = v ?? _language),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('3. Words per subtitle line',
                        style: Theme.of(context).textTheme.titleSmall),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: _wordsPerLine.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: '$_wordsPerLine',
                            onChanged: _busy
                                ? null
                                : (v) =>
                                    setState(() => _wordsPerLine = v.round()),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '$_wordsPerLine',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.subtitles),
              label: Text(_busy ? 'Working...' : 'Generate captions'),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _progress,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _shortName(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return name.length > 40 ? '${name.substring(0, 37)}...' : name;
  }
}
