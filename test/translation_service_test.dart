import 'package:flutter_test/flutter_test.dart';
import 'package:travelplanner/services/translation_service.dart';

void main() {
  final service = TranslationService();

  test('fetchLanguages returns a real, varied language list', () async {
    final languages = await service.fetchLanguages();
    final codes = languages.map((l) => l.code).toSet();

    expect(codes, containsAll(['en', 'ms', 'zh', 'ta', 'th', 'ja', 'auto']));
    expect(languages.length, greaterThan(50));
  });

  test('translate works for a pair beyond the old en/ms default (en -> ja)', () async {
    final result = await service.translate(
      'Good morning',
      from: 'en',
      to: 'ja',
    );
    expect(result, isNotEmpty);
    // Sanity check it's actually Japanese, not an echo of the English input.
    expect(result.toLowerCase(), isNot('good morning'));
  });
}
