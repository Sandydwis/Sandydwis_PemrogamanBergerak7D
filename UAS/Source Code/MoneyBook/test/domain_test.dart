import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneybook_personal/domain/ledger.dart';
import 'package:moneybook_personal/domain/receipt_parser.dart';

void main() {
  group('Pembacaan nominal rupiah', () {
    for (final pair in <String, int>{
      'Rp12.500': 12500,
      '12.500,00': 12500,
      '12,500.00': 12500,
      '12500': 12500,
      '12,500': 12500,
      '12 500': 12500,
      '12500,00': 12500,
    }.entries) {
      test(pair.key, () => expect(parseReceiptAmount(pair.key), pair.value));
    }
    for (final invalid in [
      '0',
      '-100',
      '12.50',
      '12.500,25',
      '1.2.3',
      'abc',
      '9000000000001',
    ]) {
      test(
        'menolak $invalid',
        () => expect(parseReceiptAmount(invalid), isNull),
      );
    }
  });
  group('Nota', () {
    test('total bukan tunai atau kembalian', () {
      final d = parseReceipt(
        'TOKO CONTOH\n23/10/2026\nSUBTOTAL 25.000\nTOTAL 27.500\nTUNAI 50.000\nKEMBALI 22.500',
      );
      expect(d.amount, 27500);
      expect(d.date, DateTime(2026, 10, 23));
      expect(d.merchant, 'TOKO CONTOH');
    });
    test(
      'nominal terbesar tanpa label bukan total',
      () => expect(
        parseReceipt('TOKO\nBarang 100.000\nTunai 200.000').amount,
        isNull,
      ),
    );
    test(
      'grand total lebih diutamakan',
      () =>
          expect(parseReceipt('TOTAL 25000\nGRAND TOTAL 27500').amount, 27500),
    );
    test(
      'total pada baris berikutnya',
      () =>
          expect(parseReceipt('TOKO\nTOTAL BAYAR\nRp 45.000,00').amount, 45000),
    );
    test('total bertentangan memerlukan input manual', () {
      final d = parseReceipt('TOTAL 10000\nTOTAL 20000');
      expect(d.ambiguous, isTrue);
      expect(d.amount, isNull);
    });
    test(
      'total item tidak dianggap pengeluaran',
      () => expect(parseReceipt('TOTAL ITEM 3\nTUNAI 50000').amount, isNull),
    );
    test(
      'tanggal ISO',
      () => expect(
        parseReceipt('2026-10-23\nTOTAL 10000').date,
        DateTime(2026, 10, 23),
      ),
    );
    test(
      'tanggal tidak valid tidak dinormalisasi',
      () => expect(parseReceipt('31/02/2026\nTOTAL 10000').date, isNull),
    );
    test(
      'tahun dua digit',
      () => expect(parseReceipt('23-10-26').date, DateTime(2026, 10, 23)),
    );
    test(
      'hash mengabaikan spasi dan kapital',
      () => expect(
        parseReceipt('TOKO\nTOTAL 10000').hash,
        parseReceipt('toko  total 10000').hash,
      ),
    );
    test(
      'hasil kosong tidak membuat nominal',
      () => expect(parseReceipt('').amount, isNull),
    );
  });
  group('Buku uang', () {
    LedgerEntry entry(
      String id,
      EntryKind k,
      int amount,
      DateTime date, {
      String note = '',
    }) => LedgerEntry(
      id: id,
      kind: k,
      amount: amount,
      category: k == EntryKind.income ? 'Gaji' : 'Belanja',
      date: date,
      note: note,
    );
    final now = DateTime(2026, 10, 23);
    test('saldo dihitung dari transaksi', () {
      final s = LedgerSummary([
        entry('a', EntryKind.income, 50000, now),
        entry('b', EntryKind.expense, 12000, now),
      ]);
      expect(s.balance, 38000);
      expect(s.categories['Belanja'], 12000);
    });
    test(
      'saldo negatif tetap sah untuk pencatatan',
      () => expect(
        LedgerSummary([entry('a', EntryKind.expense, 50000, now)]).balance,
        -50000,
      ),
    );
    test('filter bulan membedakan tahun dan jenis', () {
      final rows = [
        entry('a', EntryKind.income, 10, now),
        entry('b', EntryKind.expense, 20, DateTime(2025, 10, 23)),
        entry('c', EntryKind.expense, 30, now),
      ];
      expect(
        filterEntries(rows, month: now, kind: EntryKind.expense).single.id,
        'c',
      );
    });
    test('validasi nol dan kategori', () {
      expect(
        () => entry('a', EntryKind.income, 0, now).validate(),
        throwsFormatException,
      );
      expect(
        () => LedgerEntry(
          id: 'a',
          kind: EntryKind.income,
          amount: 1,
          category: 'Belanja',
          date: DateTime(2026),
        ).validate(),
        throwsFormatException,
      );
    });
    test('JSON roundtrip', () {
      final e = entry('x', EntryKind.expense, 5000, now);
      final parsed = jsonDecode(exportJson([e])) as Map;
      expect(
        LedgerEntry.fromMap(Map<String, Object?>.from(parsed['entries'][0]))
            .amount,
        5000,
      );
    });
    test('CSV mengutip dan melindungi formula', () {
      final csv = exportCsv([
        entry('a', EntryKind.expense, 10, now, note: '=SUM(1,2)'),
      ]);
      expect(csv, contains("'=SUM(1,2)"));
      expect(csv, contains('"10"'));
    });
  });
}
