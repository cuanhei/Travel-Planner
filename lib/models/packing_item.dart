/// A single packing checklist entry, backed by the `packing_items`
/// table — scoped to one trip, shared by every member of it.
class PackingItem {
  const PackingItem({
    required this.id,
    required this.tripId,
    required this.label,
    required this.category,
    required this.createdBy,
    required this.createdAt,
    this.quantity = 1,
    this.note,
    this.packed = false,
  });

  final String id;
  final String tripId;
  final String label;
  final String category;
  final int quantity;
  final String? note;
  final bool packed;
  final String createdBy;
  final DateTime createdAt;

  factory PackingItem.fromMap(Map<String, dynamic> map) {
    return PackingItem(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      label: map['label'] as String,
      category: map['category'] as String,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      note: map['note'] as String?,
      packed: map['packed'] as bool? ?? false,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'trip_id': tripId,
    'label': label,
    'category': category,
    'quantity': quantity,
    if (note != null) 'note': note,
    'packed': packed,
    'created_by': createdBy,
  };

  PackingItem copyWith({
    String? label,
    String? category,
    int? quantity,
    String? note,
    bool? packed,
  }) {
    return PackingItem(
      id: id,
      tripId: tripId,
      label: label ?? this.label,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      note: note ?? this.note,
      packed: packed ?? this.packed,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }
}
