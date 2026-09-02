/// A single logged trip expense, backed by the `expenses` table.
class Expense {
  const Expense({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.title,
    required this.category,
    required this.amount,
    required this.spentAt,
    required this.createdAt,
    this.stopPlace,
  });

  final String id;
  final String tripId;
  final String userId;
  final String title;
  final String category;
  final double amount;
  final DateTime spentAt;
  final DateTime createdAt;
  final String? stopPlace;

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      category: map['category'] as String,
      amount: (map['amount'] as num).toDouble(),
      spentAt: DateTime.parse(map['spent_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      stopPlace: map['stop_place'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'trip_id': tripId,
    'user_id': userId,
    'title': title,
    'category': category,
    'amount': amount,
    'spent_at': spentAt.toIso8601String().split('T').first,
    if (stopPlace != null) 'stop_place': stopPlace,
  };
}
