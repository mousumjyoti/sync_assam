import 'models.dart';

class SrtBuilder {
  static List<WordToken> mergeUntimed(List<WordToken> tokens) {
    final merged = <WordToken>[];
    for (final t in tokens) {
      if (t.start == 0 &&
          t.end == 0 &&
          merged.isNotEmpty &&
          _isPunctuationOnly(t.word)) {
        final prev = merged.removeLast();
        merged.add(
          WordToken(
            word: prev.word + t.word,
            start: prev.start,
            end: prev.end,
          ),
        );
      } else {
        merged.add(t);
      }
    }
    return merged;
  }

  static bool _isPunctuationOnly(String word) {
    final stripped = word.replaceAll(RegExp(r'[\s.,!?;:"\u2018\u2019\u201C\u201D()\u2013\u2014\u0964\u2026-]'), '');
    return stripped.isEmpty && word.trim().isNotEmpty;
  }

  static List<CaptionLine> buildCaptionLines(
    List<WordToken> tokens, {
    required int wordsPerLine,
    double minDuration = 0.8,
    double tailPad = 0.25,
  }) {
    final clean = mergeUntimed(
      tokens.where((t) => t.word.trim().isNotEmpty).toList(),
    );
    if (clean.isEmpty || wordsPerLine <= 0) return [];

    final lines = <CaptionLine>[];
    for (var i = 0; i < clean.length; i += wordsPerLine) {
      final chunk =
          clean.sublist(i, i + wordsPerLine > clean.length ? clean.length : i + wordsPerLine);
      final start = chunk.first.start;
      var end = chunk.last.end + tailPad;
      if (end - start < minDuration) end = start + minDuration;
      lines.add(
        CaptionLine(
          index: lines.length + 1,
          start: start,
          end: end,
          words: chunk,
        ),
      );
    }

    for (var i = 0; i < lines.length - 1; i++) {
      if (lines[i].end > lines[i + 1].start) {
        lines[i] = CaptionLine(
          index: lines[i].index,
          start: lines[i].start,
          end: lines[i + 1].start,
          words: lines[i].words,
        );
      }
    }
    return lines;
  }

  static String buildSrt(List<CaptionLine> lines) {
    if (lines.isEmpty) return '';
    final buf = StringBuffer();
    for (final line in lines) {
      buf.writeln('${line.index}');
      buf.writeln('${formatSrtTime(line.start)} --> ${formatSrtTime(line.end)}');
      buf.writeln(line.text);
      buf.writeln();
    }
    return buf.toString();
  }
}
