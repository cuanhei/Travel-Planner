import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/malaysia_city.dart';

const _poskodEndpoint = 'https://api.data.gov.my/data-catalogue/?id=poskod';

/// City/state list for the Create Trip location pickers, sourced from
/// data.gov.my's free Malaysia postcode dataset (~2,900 postcode rows,
/// deduplicated down to ~400 unique city+state pairs — small enough to
/// fetch in one request, no pagination needed).
///
/// On Android/iOS the dataset rarely changes, so it's fetched once and
/// cached in a local sqflite database — every later call reads from disk
/// instead of hitting the network again. On desktop/web it's just fetched
/// fresh each time the picker is opened, since there's no need to manage
/// a persistent cache there.
class MalaysiaLocationService {
  static const _dbName = 'malaysia_locations.db';
  static const _table = 'cities';

  Database? _db;

  bool get _persistsLocally =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<List<MalaysiaCity>> getCities() async {
    if (!_persistsLocally) return _fetchFromApi();

    final db = await _openDb();
    final cached = await db.query(_table, orderBy: 'city');
    if (cached.isNotEmpty) {
      return [
        for (final row in cached)
          MalaysiaCity(city: row['city'] as String, state: row['state'] as String),
      ];
    }

    final fetched = await _fetchFromApi();
    final batch = db.batch();
    for (final c in fetched) {
      batch.insert(
        _table,
        {'city': c.city, 'state': c.state},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    return fetched;
  }

  Future<Database> _openDb() async {
    final existing = _db;
    if (existing != null) return existing;
    final path = p.join(await getDatabasesPath(), _dbName);
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute(
        'create table $_table ('
        'city text not null, '
        'state text not null, '
        'primary key (city, state)'
        ')',
      ),
    );
    _db = db;
    return db;
  }

  Future<List<MalaysiaCity>> _fetchFromApi() async {
    final response = await http.get(Uri.parse(_poskodEndpoint));
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to load Malaysia city list (${response.statusCode})',
      );
    }

    final rows = jsonDecode(response.body) as List;
    final seen = <String>{};
    final cities = <MalaysiaCity>[];
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final city = (map['city'] as String).trim();
      final state = (map['state'] as String).trim();
      if (city.isEmpty || state.isEmpty) continue;
      if (seen.add('$city|$state')) {
        cities.add(MalaysiaCity(city: city, state: state));
      }
    }
    cities.sort((a, b) => a.city.compareTo(b.city));
    return cities;
  }
}
