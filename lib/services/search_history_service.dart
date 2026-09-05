import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class SearchHistoryService {
  static Database? _db;

  Future<Database?> _database() async {
    if (kIsWeb) return null;
    final existing = _db;
    if (existing != null) return existing;
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'search_history.db');
      final db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE search_history (
            user_id TEXT NOT NULL,
            query TEXT NOT NULL,
            searched_at INTEGER NOT NULL,
            PRIMARY KEY (user_id, query)
          )
        '''),
      );
      _db = db;
      return db;
    } catch (e) {
      debugPrint('SearchHistoryService: local database unavailable: $e');
      return null;
    }
  }

  Future<void> recordSearch(String userId, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final db = await _database();
    if (db == null) return;
    await db.insert('search_history', {
      'user_id': userId,
      'query': trimmed,
      'searched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> recentSearches(String userId, {int limit = 5}) async {
    final db = await _database();
    if (db == null) return const [];
    final rows = await db.query(
      'search_history',
      columns: ['query'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'searched_at DESC',
      limit: limit,
    );
    return [for (final row in rows) row['query'] as String];
  }
}
