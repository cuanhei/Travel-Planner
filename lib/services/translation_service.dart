import 'dart:convert';

import 'package:http/http.dart' as http;

/// A language Lingva can translate to/from — [code] is what [translate]
/// takes as `from`/`to`, [name] is what the language picker shows.
typedef TranslateLanguage = ({String code, String name});

/// Thrown when a translation request fails — a network error, a non-200
/// response, or the API's own error payload.
class TranslationServiceException implements Exception {
  TranslationServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Free-text translation via Lingva Translate — a privacy-friendly proxy
/// in front of Google Translate's own engine, no API key required.
///
/// This replaced an initial attempt using MyMemory's Translation API:
/// MyMemory is a crowd-sourced translation-*memory* lookup (matching
/// against a database of past human/community translations), not real
/// machine translation — for a phrase with no good match, it confidently
/// returns a wrong, unrelated stored phrase instead of failing.
/// Verified directly against its API: "How are you" en→ms came back
/// "Maayu nga aga" (Cebuano for "Good morning"), and ms→en came back "My
/// name is Gehna". Lingva instead reflects Google Translate's actual
/// model quality.
class TranslationService {
  TranslationService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// The official Lingva instance has been paused with no replacement
  /// announced; this community-run mirror was the only one — of several
  /// tried — that responded reliably. If it ever goes down, [translate]
  /// fails loudly with [TranslationServiceException] rather than
  /// silently falling back to MyMemory's wrong-answer behavior above.
  static const _host = 'lingva.dialectapp.org';

  /// Every language Lingva supports barely ever changes, so it's cached
  /// for the app's lifetime once fetched — shared across every
  /// [TranslationService] instance, mirroring `WeatherService`'s town-list
  /// cache.
  static List<TranslateLanguage>? _cachedLanguages;

  /// The full list of languages [translate] can use as `from`/`to`,
  /// including `'auto'` ("Detect language") for `from`. Fetched from
  /// Lingva itself rather than hardcoded, so it stays in sync with
  /// whatever that instance actually supports.
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

  /// Translates [text] from [from] to [to] (ISO 639-1 codes, e.g. `'en'`
  /// to `'ms'`). Returns `''` for blank input rather than round-tripping
  /// to the API for nothing.
  Future<String> translate(
    String text, {
    required String from,
    required String to,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';

    // pathSegments (rather than manual string concatenation) percent-
    // encodes trimmed correctly even if it contains '/', '?', '&', etc.
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
