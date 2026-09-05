import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();

  static String? _url;
  static String? _publishableKey;

  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
    _url = dotenv.maybeGet('SUPABASE_URL');
    _publishableKey = dotenv.maybeGet('SUPABASE_ANON_KEY');
  }

  static String get url => _url ?? '';

  static String get publishableKey => _publishableKey ?? '';

  static bool get isConfigured =>
      url.isNotEmpty &&
      url != 'https://your-project-ref.supabase.co' &&
      publishableKey.isNotEmpty &&
      publishableKey != 'your-anon-public-key';

  static SupabaseClient get client => Supabase.instance.client;
}

Future<T> retryOnJwtClockSkew<T>(Future<T> Function() action) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST303' || attempt >= 2) rethrow;
      await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }
}
