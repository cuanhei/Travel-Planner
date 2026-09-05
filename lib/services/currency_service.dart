import 'dart:convert';

import 'package:http/http.dart' as http;

class CurrencyServiceException implements Exception {
  CurrencyServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}

class CurrencyRates {
  const CurrencyRates({required this.rates, required this.date});

  final Map<String, double> rates;
  final DateTime date;
}

class CurrencyService {
  CurrencyService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://api.frankfurter.dev/v1';

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
    return CurrencyRates(
      rates: rates,
      date: DateTime.parse(decoded['date'] as String),
    );
  }
}
