import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:moneybook_personal/data/ledger_repository.dart';
import 'package:moneybook_personal/domain/ledger.dart';
import 'package:moneybook_personal/domain/receipt_parser.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late SqliteLedgerRepository repo;
  LedgerEntry e(
    String id,
    int amount, {
    String? hash,
    EntryKind kind = EntryKind.expense,
  }) => LedgerEntry(
    id: id,
    kind: kind,
    amount: amount,
    category: kind == EntryKind.income ? 'Gaji' : 'Belanja',
    date: DateTime(2026, 10, 23),
    receiptHash: hash,
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('mb_test_');
    repo = await SqliteLedgerRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/test.db',
    );
  });
  tearDown(() async {
    await repo.close();
    await temp.delete(recursive: true);
  });
  test(
    'penyimpanan baru kosong',
    () async => expect(await repo.readAll(), isEmpty),
  );
  test('tambah, ubah dan hapus menghitung ulang saldo', () async {
    await repo.save(e('income', 100000, kind: EntryKind.income));
    await repo.save(e('expense', 30000));
    expect(LedgerSummary(await repo.readAll()).balance, 70000);
    await repo.save(e('expense', 40000));
    expect(LedgerSummary(await repo.readAll()).balance, 60000);
    await repo.delete('expense');
    expect(LedgerSummary(await repo.readAll()).balance, 100000);
  });
  test('bertahan setelah database ditutup dan dibuka', () async {
    await repo.save(e('a', 25000));
    await repo.close();
    repo = await SqliteLedgerRepository.open(
      factory: databaseFactoryFfi,
      path: '${temp.path}/test.db',
    );
    expect((await repo.readAll()).single.amount, 25000);
  });
  test(
    'nota ganda diblokir dan hanya bisa dilanjutkan secara eksplisit',
    () async {
      final hash = parseReceipt('TOKO\nTOTAL 25000').hash;
      await repo.save(e('a', 25000, hash: hash));
      await expectLater(
        repo.save(e('b', 25000, hash: hash)),
        throwsA(isA<DuplicateReceipt>()),
      );
      expect((await repo.readAll()).length, 1);
      await repo.save(e('b', 25000, hash: hash), allowDuplicate: true);
      expect((await repo.readAll()).length, 2);
    },
  );
  test('edit nota sendiri tidak dianggap duplikat', () async {
    final h = parseReceipt('TOTAL 25000').hash;
    await repo.save(e('a', 25000, hash: h));
    await repo.save(e('a', 27000, hash: h));
    expect((await repo.readAll()).single.amount, 27000);
  });
  test('validasi gagal tidak mengubah database', () async {
    await repo.save(e('a', 10));
    await expectLater(repo.save(e('b', 0)), throwsFormatException);
    expect((await repo.readAll()).length, 1);
  });
  test('database menolak nominal negatif di luar repository', () async {
    await expectLater(
      repo.db.insert('entries', e('a', -10).toMap()),
      throwsA(isA<DatabaseException>()),
    );
    expect(await repo.readAll(), isEmpty);
  });
  test('hapus semua membersihkan data dan rekap', () async {
    await repo.save(e('a', 25000));
    await repo.clear();
    expect(LedgerSummary(await repo.readAll()).expense, 0);
  });
}
