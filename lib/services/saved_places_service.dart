import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nearby_place.dart';
import '../models/saved_place.dart';
import 'supabase_config.dart';

/// Backend for the Saved Places module: a live, per-user bookmark list
/// (personal — not shared with trip members, unlike the trip-scoped
/// modules) backed by `saved_places`.
class SavedPlacesService {
  SavedPlacesService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Stream<List<SavedPlace>> watchSavedPlaces() {
    return _client
        .from('saved_places')
        .stream(primaryKey: ['id'])
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(SavedPlace.fromMap).toList());
  }

  /// Whether [placeId] is already bookmarked by the signed-in user —
  /// used to pick the bookmark icon's filled/outline state up front.
  Future<bool> isSaved(String placeId) async {
    final rows = await _client
        .from('saved_places')
        .select('id')
        .eq('user_id', _uid)
        .eq('place_id', placeId)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Upsert on `(user_id, place_id)` — bookmarking the same place twice
  /// (e.g. from two different searches) just refreshes its saved copy
  /// instead of erroring or duplicating the row.
  Future<void> savePlace(NearbyPlace place) async {
    await _client.from('saved_places').upsert({
      'user_id': _uid,
      'place_id': place.id,
      'name': place.name,
      'address': place.address,
      'latitude': place.latitude,
      'longitude': place.longitude,
      'primary_type': place.primaryType,
      'photo_url': place.photoUrl,
    }, onConflict: 'user_id,place_id');
  }

  Future<void> unsavePlace(String placeId) async {
    await _client
        .from('saved_places')
        .delete()
        .eq('user_id', _uid)
        .eq('place_id', placeId);
  }
}
