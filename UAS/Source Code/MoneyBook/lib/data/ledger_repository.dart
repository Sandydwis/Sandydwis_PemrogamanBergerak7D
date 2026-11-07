import 'package:sqflite/sqflite.dart';

import '../domain/ledger.dart';

class DuplicateReceipt implements Exception {
  @override
  String toString() =>
      'Nota yang sama sudah pernah dicatat. Periksa riwayat sebelum menyimpan lagi.';
}

abstract class LedgerRepository {
  Future<List<LedgerEntry>> readAll();
  Future<void> save(LedgerEntry entry, {bool allowDuplicate = false});
  Future<void> delete(String id);
  Future<void> clear();
  Future<void> close();
}

class SqliteLedgerRepository implements LedgerRepository {
  SqliteLedgerRepository._(this.db);
  final Database db;

  static Future<SqliteLedgerRepository> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final location =
        path ?? '${await f.getDatabasesPath()}/moneybook_personal_v1.db';
    final db = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''CREATE TABLE entries (
        id TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL CHECK(kind IN ('income','expense')),
        amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 9000000000000),
        category TEXT NOT NULL, date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '', merchant TEXT NOT NULL DEFAULT '',
        receipt_hash TEXT
      )''');
          await db.execute('CREATE INDEX entries_date ON entries(date DESC)');
          await db.execute(
            'CREATE INDEX entries_receipt ON entries(receipt_hash)',
          );
        },
      ),
    );
    return SqliteLedgerRepository._(db);
  }

  @override
  Future<List<LedgerEntry>> readAll() async => (await db.query(
    'entries',
    orderBy: 'date DESC, rowid DESC',
  )).map(LedgerEntry.fromMap).toList();

  @override
  Future<void> save(LedgerEntry entry, {bool allowDuplicate = false}) async {
    entry.validate();
    await db.transaction((txn) async {
      if (entry.receiptHash != null && !allowDuplicate) {
        final matches = await txn.query(
          'entries',
          columns: ['id'],
          where: 'receipt_hash = ? AND id != ?',
          whereArgs: [entry.receiptHash, entry.id],
          limit: 1,
        );
        if (matches.isNotEmpty) throw DuplicateReceipt();
      }
      await txn.insert(
        'entries',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<void> delete(String id) async {
    await db.delete('entries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clear() async {
    await db.delete('entries');
  }

  @override
  Future<void> close() => db.close();
}

// Explicitly temporary storage for UI tests and browser preview; Android uses SQLite.
class MemoryLedgerRepository implements LedgerRepository {
  final Map<String, LedgerEntry> _entries = {};
  @override
  Future<List<LedgerEntry>> readAll() async =>
      _entries.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  @override
  Future<void> save(LedgerEntry entry, {bool allowDuplicate = false}) async {
    entry.validate();
    if (!allowDuplicate &&
        entry.receiptHash != null &&
        _entries.values.any(
          (e) => e.id != entry.id && e.receiptHash == entry.receiptHash,
        )) {
      throw DuplicateReceipt();
    }
    _entries[entry.id] = entry;
  }

  @override
  Future<void> delete(String id) async {
    _entries.remove(id);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }

  @override
  Future<void> close() async {}
}
