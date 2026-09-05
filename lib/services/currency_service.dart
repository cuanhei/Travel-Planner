import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when [CurrencyService] can't fetch live rates — a network
/// failure or a non-200 response.
class CurrencyServiceException implements Exception {
  CurrencyServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Exchange rates for a set of currencies, all relative to one of them
/// (whichever [CurrencyService.fetchRates] was called with as the first
/// entry) — e.g. `{'USD': 1.0, 'MYR': 4.72, 'SGD': 1.34}` means 1 USD
/// buys 4.72 MYR or 1.34 SGD today. [date] is the day the underlying
/// reference rates were published (banks don't publish new rates on
/// weekends/holidays, so this can lag "today").
class CurrencyRates {
  const CurrencyRates({required this.rates, required this.date});

  final Map<String, double> rates;
  final DateTime date;
}

/// Live exchange rates via Frankfurter (frankfurter.dev), which wraps
/// the European Central Bank's daily reference rates — free, no API
/// key, no rate limit, refreshed once per ECB business day. Same
/// "no-key public API" shape as [WeatherService]'s MET Malaysia feed.
class CurrencyService {
  CurrencyService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://api.frankfurter.dev/v1';

  /// Rates for every currency in [currencies], relative to
  /// `currencies.first` (which comes back pinned at exactly 1.0 — the
  /// API only returns rates for currencies *other than* the base, so
  /// that entry is added locally rather than trusting the response to
  /// include it).
  Future<CurrencyRates> fetchRates(List<String> currencies) async {
    if (currencies.length < 2) {
      throw CurrencyServiceException(
        'Need at least two currencies to fetch rates for.',
      );
    }
    final base = currencies.first;
    final symbols = currencies.skip(1).join(',');
    final uri = Uri.parse(
      '$_baseUrl/latest',
    ).replace(queryParameters: {'base': base, 'symbols': symbols});

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw CurrencyServiceException(
        'Exchange rate request failed (${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final ratesJson = decoded['rates'] as Map<String, dynamic>;
    final rates = <String, double>{
      base: 1.0,
      for (final entry in ratesJson.entries)
        entry.key: (entry.value as num).toDouble(),
    };
    return CurrencyRates(rates: rates, date: DateTime.parse(decoded['date'] as String));
  }
}
