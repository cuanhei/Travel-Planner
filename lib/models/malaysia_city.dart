/// A Malaysian town/city and the state it belongs to, sourced from
/// data.gov.my's postcode dataset (deduplicated — the source data has one
/// row per postcode, so the same city/state pair repeats many times).
class MalaysiaCity {
  const MalaysiaCity({required this.city, required this.state});

  final String city;
  final String state;

  String get label => '$city, $state';

  @override
  bool operator ==(Object other) =>
      other is MalaysiaCity && other.city == city && other.state == state;

  @override
  int get hashCode => Object.hash(city, state);
}
