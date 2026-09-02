import 'strings/auth_strings.dart';
import 'strings/budget_strings.dart';
import 'strings/common_strings.dart';
import 'strings/community_strings.dart';
import 'strings/explore_strings.dart';
import 'strings/group_strings.dart';
import 'strings/saved_strings.dart';
import 'strings/transport_strings.dart';
import 'strings/trip_strings.dart';
import 'strings/utilities_strings.dart';
import 'strings/weather_strings.dart';

/// Every module contributes its own `Map<languageCode, Map<key, text>>` —
/// keeping modules in separate files means each can be translated
/// independently without merge conflicts. This just combines them all by
/// language code for `tr()` (see `locale_service.dart`) to look up.
final Map<String, Map<String, String>> translations = _merge([
  commonStrings,
  authStrings,
  tripStrings,
  weatherStrings,
  transportStrings,
  exploreStrings,
  communityStrings,
  savedStrings,
  budgetStrings,
  utilitiesStrings,
  groupStrings,
]);

Map<String, Map<String, String>> _merge(
  List<Map<String, Map<String, String>>> sources,
) {
  final result = <String, Map<String, String>>{};
  for (final source in sources) {
    for (final entry in source.entries) {
      result.putIfAbsent(entry.key, () => {}).addAll(entry.value);
    }
  }
  return result;
}
