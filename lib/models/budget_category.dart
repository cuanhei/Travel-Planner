/// A planned spending category for a trip, backed by `budget_categories`.
/// Icon/color are a purely visual concern owned by the UI (matched by
/// [label]) — the backend only tracks the label and planned amount.
class BudgetCategoryData {
  const BudgetCategoryData({
    required this.id,
    required this.tripId,
    required this.label,
    required this.plannedAmount,
  });

  final String id;
  final String tripId;
  final String label;
  final double plannedAmount;

  factory BudgetCategoryData.fromMap(Map<String, dynamic> map) {
    return BudgetCategoryData(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      label: map['label'] as String,
      plannedAmount: (map['planned_amount'] as num).toDouble(),
    );
  }
}
