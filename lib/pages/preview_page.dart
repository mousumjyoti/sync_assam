import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../srt_builder.dart';

class PreviewPage extends StatefulWidget {
  const PreviewPage({
    super.key,
    required this.audioPath,
    required this.tokens,
    required this.wordsPerLine,
  });

  final String audioPath;
  final List<WordToken> tokens;
  final int wordsPerLine;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  final _player = AudioPlayer();
  late int _wordsPerLine;
  List<CaptionLine> _lines = [];
  double _positionSeconds = 0;
  bool _showRaw = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _wordsPerLine = widget.wordsPerLine;
    _rebuild();
    _init();
  }

  void _rebuild() {
    setState(() {
      _lines = SrtBuilder.buildCaptionLines(
        widget.tokens,
        wordsPerLine: _wordsPerLine,
      );
    });
  }

  Future<void> _init() async {
    try {
      await _player.setFilePath(widget.audioPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open audio for preview: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  CaptionLine? get _currentLine {
    for (final line in _lines) {
      if (_positionSeconds >= line.start && _positionSeconds < line.end) {
        return line;
      }
    }
    return null;
  }

  Future<void> _export() async {
    final srt = SrtBuilder.buildSrt(_lines);
    if (srt.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final base = widget.audioPath
        .split(RegExp(r'[\\/]'))
        .last
        .split('.')
        .first;
    final file = File('${dir.path}/$base.srt');
    await file.writeAsString(srt);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '$base.srt',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        actions: [
          IconButton(
            icon: Icon(_showRaw ? Icons.play_circle_outline : Icons.text_snippet_outlined),
            tooltip: _showRaw ? 'Show captions' : 'Show raw SRT',
            onPressed: () => setState(() => _showRaw = !_showRaw),
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: 'Export .srt',
            onPressed: _lines.isEmpty ? null : _export,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _showRaw ? _buildRawSrt() : _buildCaptionStage(),
          ),
          if (_lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Words/line: '),
                  IconButton(
                    onPressed: _wordsPerLine > 1
                        ? () {
                            setState(() => _wordsPerLine--);
                            _rebuild();
                          }
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_wordsPerLine'),
                  IconButton(
                    onPressed: _wordsPerLine < 10
                        ? () {
                            setState(() => _wordsPerLine++);
                            _rebuild();
                          }
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snapshot) {
              final pos = snapshot.data ?? Duration.zero;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final seconds = pos.inMilliseconds / 1000.0;
                if (seconds != _positionSeconds && mounted) {
                  setState(() => _positionSeconds = seconds);
                }
              });
              return Column(
                children: [
                  StreamBuilder<Duration?>(
                    stream: _player.durationStream,
                    builder: (context, snap) {
                      final total = snap.data ?? Duration.zero;
                      return Slider(
                        value: total.inMilliseconds == 0
                            ? 0
                            : pos.inMilliseconds
                                .clamp(0, total.inMilliseconds)
                                .toDouble(),
                        max: total.inMilliseconds == 0
                            ? 1
                            : total.inMilliseconds.toDouble(),
                        onChanged: total.inMilliseconds == 0
                            ? null
                            : (v) => _player
                                .seek(Duration(milliseconds: v.round())),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        StreamBuilder<PlayerState>(
                          stream: _player.playerStateStream,
                          builder: (context, snap) {
                            final playing =
                                snap.data?.playing ?? false;
                            return IconButton.filled(
                              onPressed: _loading
                                  ? null
                                  : () => playing
                                      ? _player.pause()
                                      : _player.play(),
                              icon: Icon(playing
                                  ? Icons.pause
                                  : Icons.play_arrow),
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${formatClock(_positionSeconds)} / '
                          '${formatClock(_player.duration?.inMilliseconds != null ? _player.duration!.inMilliseconds / 1000 : 0)}',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCaptionStage() {
    final line = _currentLine;
    return Container(
      width: double.infinity,
      color: Colors.black87,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: line == null
          ? Text(
              _lines.isEmpty ? 'No captions' : '...',
              style: const TextStyle(color: Colors.white54, fontSize: 22),
            )
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: line.words.map((w) {
                final active =
                    _positionSeconds >= w.start && _positionSeconds < w.end;
                return Text(
                  w.word,
                  style: TextStyle(
                    color: active ? Colors.amber : Colors.white,
                    fontSize: 28,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildRawSrt() {
    final text = SrtBuilder.buildSrt(_lines);
    return Container(
      width: double.infinity,
      color: Colors.black87,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: SelectableText(
          text.isEmpty ? 'No captions' : text,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
