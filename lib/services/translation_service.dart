import 'dart:convert';

import 'package:http/http.dart' as http;

typedef TranslateLanguage = ({String code, String name});

class TranslationServiceException implements Exception {
  TranslationServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TranslationService {
  TranslationService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _host = 'lingva.dialectapp.org';

  static List<TranslateLanguage>? _cachedLanguages;

  Future<List<TranslateLanguage>> fetchLanguages() async {
    final cached = _cachedLanguages;
    if (cached != null) return cached;

    final uri = Uri(scheme: 'https', host: _host, path: '/api/v1/languages');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw TranslationServiceException(
        'Could not load the list of languages (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final languages = (decoded['languages'] as List)
        .map(
          (l) => (
            code: (l as Map<String, dynamic>)['code'] as String,
            name: l['name'] as String,
          ),
        )
        .toList();
    _cachedLanguages = languages;
    return languages;
  }

  Future<String> translate(
    String text, {
    required String from,
    required String to,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri(
      scheme: 'https',
      host: _host,
      pathSegments: ['api', 'v1', from, to, trimmed],
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw TranslationServiceException(
        'Translation request failed (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final translation = decoded['translation'] as String?;
    if (translation == null) {
      throw TranslationServiceException(
        (decoded['error'] as String?) ?? 'Translation failed.',
      );
    }
    return translation;
  }
}
