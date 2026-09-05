import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nearby_place.dart';
import '../models/saved_place.dart';
import 'supabase_config.dart';

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

  Future<bool> isSaved(String placeId) async {
    final rows = await _client
        .from('saved_places')
        .select('id')
        .eq('user_id', _uid)
        .eq('place_id', placeId)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

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
