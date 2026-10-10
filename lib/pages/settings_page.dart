import 'dart:convert';

import 'package:flutter/material.dart';

import '../settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _jsonController = TextEditingController();
  final _bucketController = TextEditingController();
  String _location = 'us-central1';
  AppSettings? _loaded;

  @override
  void initState() {
    super.initState();
    SettingsStore.load().then((s) {
      if (!mounted) return;
      setState(() {
        _loaded = s;
        _jsonController.text = s.serviceAccountJson;
        _bucketController.text = s.bucket;
        _location = s.location;
      });
    });
  }

  @override
  void dispose() {
    _jsonController.dispose();
    _bucketController.dispose();
    super.dispose();
  }

  String? _validateJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Required to use the app.';
    try {
      final map = jsonDecode(trimmed);
      if (map is! Map<String, dynamic>) {
        return 'Not a JSON object.';
      }
      for (final key in ['client_email', 'private_key', 'token_uri']) {
        if (map[key] is! String || (map[key] as String).isEmpty) {
          return 'Missing "$key".';
        }
      }
      return null;
    } catch (_) {
      return 'Invalid JSON.';
    }
  }

  Future<void> _save() async {
    final error = _validateJson(_jsonController.text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Service account JSON: $error')),
      );
      return;
    }
    final settings = AppSettings(
      serviceAccountJson: _jsonController.text.trim(),
      location: _location,
      bucket: _bucketController.text.trim(),
    );
    await SettingsStore.save(settings);
    if (!mounted) return;
    Navigator.pop(context, settings);
  }

  Future<void> _clear() async {
    await SettingsStore.clear();
    if (!mounted) return;
    setState(() {
      _jsonController.clear();
      _bucketController.clear();
      _location = 'us-central1';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings cleared.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear all',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Service account JSON',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Google Cloud Console → IAM → Service accounts → Keys → '
              'Add key → JSON. Paste the whole file here. The service '
              'account needs the "Cloud Speech Client" role (or Cloud '
              'Speech Editor / Administrator) on the same project.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _jsonController,
              maxLines: 8,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '{"type": "service_account", ...}',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'API location',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _location,
              items: kLocationChoices
                  .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                  .toList(),
              onChanged: (v) => setState(() => _location = v ?? _location),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            Text(
              'Regional locations are routed to their own API endpoint '
              '(e.g. asia-southeast1-speech.googleapis.com). Assamese '
              '(as-IN) works with model chirp_2 in global, us-central1, us, '
              'eu, europe-west4 and asia-southeast1.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text(
              'Cloud Storage bucket (optional)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _bucketController,
              decoration: const InputDecoration(
                hintText: 'my-bucket-name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Needed only for audio longer than about 60 seconds. The app '
              'uploads temporary files here, then deletes them. The service '
              'account needs "Storage Object Admin" on this bucket. For a '
              'regional API location, the bucket must be in that same region.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
