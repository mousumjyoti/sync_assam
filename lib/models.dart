class SupportedLanguage {
  const SupportedLanguage(this.code, this.label);

  final String code;
  final String label;
}

const List<SupportedLanguage> kSupportedLanguages = [
  SupportedLanguage('as-IN', 'Assamese (as-IN)'),
  SupportedLanguage('hi-IN', 'Hindi (hi-IN)'),
  SupportedLanguage('en-US', 'English (en-US)'),
];

class WordToken {
  const WordToken({
    required this.word,
    required this.start,
    required this.end,
  });

  final String word;
  final double start;
  final double end;
}

class CaptionLine {
  CaptionLine({
    required this.index,
    required this.start,
    required this.end,
    required this.words,
  });

  final int index;
  final double start;
  final double end;
  final List<WordToken> words;

  String get text => words.map((w) => w.word).join(' ');
}

double parseOffsetSeconds(String raw) {
  final trimmed = raw.trim();
  if (trimmed.endsWith('s')) {
    return double.tryParse(trimmed.substring(0, trimmed.length - 1)) ?? 0;
  }
  return double.tryParse(trimmed) ?? 0;
}

String formatSrtTime(double seconds) {
  if (seconds < 0) seconds = 0;
  final totalMs = (seconds * 1000).round();
  final ms = totalMs % 1000;
  final totalSec = totalMs ~/ 1000;
  final s = totalSec % 60;
  final m = (totalSec ~/ 60) % 60;
  final h = totalSec ~/ 3600;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)},${ms.toString().padLeft(3, '0')}';
}

String formatClock(double seconds) {
  if (seconds < 0) seconds = 0;
  final totalSec = seconds.floor();
  final s = totalSec % 60;
  final m = (totalSec ~/ 60) % 60;
  final h = totalSec ~/ 60;
  String two(int v) => v.toString().padLeft(2, '0');
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '${two(m)}:${two(s)}';
}
