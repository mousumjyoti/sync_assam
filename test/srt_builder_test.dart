import 'package:flutter_test/flutter_test.dart';

import 'package:sync_assam/models.dart';
import 'package:sync_assam/srt_builder.dart';

WordToken w(String word, double start, double end) =>
    WordToken(word: word, start: start, end: end);

void main() {
  group('parseOffsetSeconds', () {
    test('parses duration strings', () {
      expect(parseOffsetSeconds('3.5s'), 3.5);
      expect(parseOffsetSeconds('0.000000001s'), closeTo(1e-9, 1e-12));
      expect(parseOffsetSeconds('12s'), 12.0);
      expect(parseOffsetSeconds('5'), 5.0);
      expect(parseOffsetSeconds('bogus'), 0.0);
    });
  });

  group('formatSrtTime', () {
    test('formats hh:mm:ss,mmm', () {
      expect(formatSrtTime(0), '00:00:00,000');
      expect(formatSrtTime(1.5), '00:00:01,500');
      expect(formatSrtTime(65.123), '00:01:05,123');
      expect(formatSrtTime(3671.9995), '01:01:12,000');
      expect(formatSrtTime(-3), '00:00:00,000');
    });
  });

  group('buildCaptionLines', () {
    test('groups words by wordsPerLine', () {
      final tokens = [
        w('hello', 0, 0.5),
        w('world', 0.5, 1.0),
        w('again', 1.0, 1.4),
      ];
      final lines = SrtBuilder.buildCaptionLines(tokens, wordsPerLine: 2);
      expect(lines.length, 2);
      expect(lines[0].words.length, 2);
      expect(lines[1].words.length, 1);
      expect(lines[0].text, 'hello world');
      expect(lines[0].start, 0);
      expect(lines[1].start, 1.0);
    });

    test('empty tokens produce no lines', () {
      expect(
        SrtBuilder.buildCaptionLines([], wordsPerLine: 3),
        isEmpty,
      );
    });

    test('zero or negative wordsPerLine produces no lines', () {
      final tokens = [w('a', 0, 1)];
      expect(SrtBuilder.buildCaptionLines(tokens, wordsPerLine: 0), isEmpty);
      expect(SrtBuilder.buildCaptionLines(tokens, wordsPerLine: -2), isEmpty);
    });

    test('minimum duration enforced', () {
      final tokens = [w('short', 10.0, 10.1)];
      final lines = SrtBuilder.buildCaptionLines(tokens, wordsPerLine: 2);
      expect(lines.single.end - lines.single.start,
          greaterThanOrEqualTo(0.8));
      expect(lines.single.end, 10.8);
    });

    test('overlapping lines are clamped', () {
      final tokens = [
        w('one', 0, 2.0),
        w('two', 2.05, 3.0),
      ];
      final lines = SrtBuilder.buildCaptionLines(tokens, wordsPerLine: 1);
      expect(lines[0].end, lessThanOrEqualTo(lines[1].start));
    });

    test('punctuation with no timing merges into previous word', () {
      final tokens = [
        w('hello', 0, 0.5),
        w('.', 0, 0),
        w('world', 0.6, 1.0),
      ];
      final lines = SrtBuilder.buildCaptionLines(tokens, wordsPerLine: 2);
      expect(lines.single.text, 'hello. world');
      expect(lines.length, 1);
    });

    test('whitespace-only tokens dropped', () {
      final tokens = [w('  ', 0, 0), w('word', 1, 2)];
      final lines = SrtBuilder.buildCaptionLines(tokens, wordsPerLine: 5);
      expect(lines.single.words.length, 1);
    });
  });

  group('buildSrt', () {
    test('standard srt blocks', () {
      final tokens = [
        w('hello', 0, 0.5),
        w('world', 0.5, 1.0),
      ];
      final lines = SrtBuilder.buildCaptionLines(tokens, wordsPerLine: 1);
      final srt = SrtBuilder.buildSrt(lines).replaceAll('\r\n', '\n');
      final blocks = srt.trim().split('\n\n');
      expect(blocks.length, 2);
      expect(blocks[0].trim().split('\n').length, 3);
      expect(blocks[0], contains('00:00:00,000 --> 00:00:00,500'));
      expect(blocks[0].trim().split('\n').first, '1');
      expect(blocks[1].trim().split('\n').first, '2');
      expect(blocks[0], contains('hello'));
      expect(blocks[1], contains('world'));
    });

    test('empty lines give empty srt', () {
      expect(SrtBuilder.buildSrt([]), '');
    });
  });
}
