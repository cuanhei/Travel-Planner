/// Prevents duplicate loads and rejects results started before a schedule edit.
class RecommendationRequests<K> {
  int _generation = 0;
  final Set<K> _pending = {};

  int? begin(K key) => _pending.add(key) ? _generation : null;

  bool complete(K key, int ticket) {
    if (ticket != _generation) return false;
    return _pending.remove(key);
  }

  void invalidate() {
    _generation++;
    _pending.clear();
  }
}
