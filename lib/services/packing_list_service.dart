import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/packing_item.dart';
import '../models/trip.dart';
import 'locale_service.dart';
import 'supabase_config.dart';

/// One rule-based starter suggestion — not yet an inserted [PackingItem],
/// just the label/category/quantity/note [PackingListService.generateSuggestedItems]
/// would insert.
typedef PackingSuggestion = ({
  String label,
  String category,
  int quantity,
  String? note,
});

/// Rule-based starter checklist for [trip] — no external calls (the
/// app's only weather API covers Malaysia and needs GPS coordinates, not
/// a free-text destination, so this leans on trip length, the trip's
/// own dates, and destination keywords instead). Always includes the
/// same basics the old hardcoded mock list had, then layers on
/// destination- and season-specific extras:
/// - Clothing quantities scale with trip length (capped at a week's
///   worth — nobody packs 20 shirts, they do laundry).
/// - A beach/island-sounding destination adds swimwear-focused extras;
///   a highland-sounding one adds warmer layers instead.
/// - A trip whose dates fall in Malaysia's Nov–Mar wet season gets rain
///   gear called out explicitly, not just the always-included jacket.
List<PackingSuggestion> buildSuggestedItems(Trip trip) {
  final days = trip.days == 0 ? 3 : trip.days;
  final clothingQty = days.clamp(1, 7);
  final destination = trip.destination.toLowerCase();

  bool matchesAny(List<String> keywords) =>
      keywords.any((k) => destination.contains(k));

  final isBeach = matchesAny([
    'beach', 'island', 'pantai', 'pulau',
    'langkawi', 'redang', 'perhentian', 'tioman',
  ]);
  final isHighland = matchesAny([
    'highland', 'hill', 'mountain', 'cameron', 'genting', 'fraser',
  ]);

  bool spansWetSeason() {
    final start = trip.startDate;
    final end = trip.endDate;
    if (start == null || end == null) return false;
    const wetMonths = {11, 12, 1, 2, 3};
    var cursor = DateTime(start.year, start.month);
    final endMonth = DateTime(end.year, end.month);
    while (!cursor.isAfter(endMonth)) {
      if (wetMonths.contains(cursor.month)) return true;
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return false;
  }

  final wetSeason = spansWetSeason();

  final suggestions = <PackingSuggestion>[
    (
      label: tr('utilities_item_light_shirts_shorts'),
      category: 'Clothing',
      quantity: clothingQty,
      note: null,
    ),
    (
      label: tr('utilities_item_walking_shoes'),
      category: 'Clothing',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_sunscreen'),
      category: 'Toiletries',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_toothbrush'),
      category: 'Toiletries',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_insect_repellent'),
      category: 'Toiletries',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_phone_charger'),
      category: 'Electronics',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_power_bank'),
      category: 'Electronics',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_universal_adapter'),
      category: 'Electronics',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_passport_ic'),
      category: 'Documents',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_hotel_booking'),
      category: 'Documents',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_travel_insurance'),
      category: 'Documents',
      quantity: 1,
      note: null,
    ),
    (
      label: tr('utilities_item_rain_jacket'),
      category: 'Clothing',
      quantity: 1,
      note: wetSeason ? tr('utilities_suggestion_note_wet_season') : null,
    ),
  ];

  if (isBeach) {
    suggestions.addAll([
      (
        label: tr('utilities_item_swimwear'),
        category: 'Clothing',
        quantity: 2,
        note: null,
      ),
      (
        label: tr('utilities_item_beach_towel'),
        category: 'Clothing',
        quantity: 1,
        note: null,
      ),
      (
        label: tr('utilities_item_flip_flops'),
        category: 'Clothing',
        quantity: 1,
        note: null,
      ),
    ]);
  } else {
    suggestions.add((
      label: tr('utilities_item_swimwear'),
      category: 'Clothing',
      quantity: 1,
      note: null,
    ));
  }

  if (isHighland) {
    suggestions.add((
      label: tr('utilities_item_warm_jacket'),
      category: 'Clothing',
      quantity: 1,
      note: tr('utilities_suggestion_note_highland'),
    ));
  }

  if (wetSeason) {
    suggestions.addAll([
      (
        label: tr('utilities_item_umbrella'),
        category: 'Clothing',
        quantity: 1,
        note: null,
      ),
      (
        label: tr('utilities_item_waterproof_bag'),
        category: 'Electronics',
        quantity: 1,
        note: tr('utilities_suggestion_note_wet_season'),
      ),
    ]);
  }

  if (days >= 8) {
    suggestions.add((
      label: tr('utilities_item_laundry_bag'),
      category: 'Clothing',
      quantity: 1,
      note: tr('utilities_suggestion_note_long_trip'),
    ));
  }

  return suggestions;
}

/// Backend for the Packing List module: a live, per-trip, shared
/// checklist (any trip member can add/check off/remove items — mirrors
/// Budget's `budget_categories`), plus [generateSuggestedItems] to seed
/// it from [buildSuggestedItems].
class PackingListService {
  PackingListService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Stream<List<PackingItem>> watchItems(String tripId) {
    return _client
        .from('packing_items')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at')
        .map((rows) => rows.map(PackingItem.fromMap).toList());
  }

  Future<PackingItem> addItem({
    required String tripId,
    required String label,
    required String category,
    int quantity = 1,
    String? note,
    bool packed = false,
  }) async {
    final row = await _client
        .from('packing_items')
        .insert(
          PackingItem(
            id: '',
            tripId: tripId,
            label: label,
            category: category,
            quantity: quantity,
            note: note,
            packed: packed,
            createdBy: _uid,
            createdAt: DateTime.now(),
          ).toInsertMap(),
        )
        .select()
        .single();
    return PackingItem.fromMap(row);
  }

  Future<void> updateItem(
    String id, {
    required String label,
    required String category,
    required int quantity,
    String? note,
    required bool packed,
  }) async {
    await _client
        .from('packing_items')
        .update({
          'label': label,
          'category': category,
          'quantity': quantity,
          'note': note,
          'packed': packed,
        })
        .eq('id', id);
  }

  Future<void> setPacked(String id, bool packed) async {
    await _client
        .from('packing_items')
        .update({'packed': packed})
        .eq('id', id);
  }

  Future<void> deleteItem(String id) async {
    await _client.from('packing_items').delete().eq('id', id);
  }

  /// Inserts [buildSuggestedItems]'s starter checklist for [trip],
  /// skipping any label already in [existingItems] (case-insensitive) —
  /// tapping "Auto-generate" again after editing the list tops it up
  /// with whatever's still missing instead of duplicating everything.
  /// Returns how many items were actually added.
  Future<int> generateSuggestedItems(
    Trip trip,
    List<PackingItem> existingItems,
  ) async {
    final existingLabels = existingItems
        .map((i) => i.label.toLowerCase())
        .toSet();
    final suggestions = buildSuggestedItems(trip)
        .where((s) => !existingLabels.contains(s.label.toLowerCase()))
        .toList();
    if (suggestions.isEmpty) return 0;
    await _client.from('packing_items').insert([
      for (final s in suggestions)
        {
          'trip_id': trip.id,
          'label': s.label,
          'category': s.category,
          'quantity': s.quantity,
          if (s.note != null) 'note': s.note,
          'created_by': _uid,
        },
    ]);
    return suggestions.length;
  }
}
