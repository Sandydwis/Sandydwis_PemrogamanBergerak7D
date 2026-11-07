import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:moneybook_personal/app.dart';
import 'package:moneybook_personal/data/ledger_repository.dart';
import 'package:moneybook_personal/data/receipt_service.dart';
import 'package:moneybook_personal/domain/ledger.dart';
import 'package:moneybook_personal/domain/receipt_parser.dart';

class FakeReceipts implements ReceiptService {
  ReceiptCapture? next;
  bool fail = false;
  @override
  Future<ReceiptCapture?> capture(ReceiptSource source) async {
    if (fail) throw const FormatException('Teks belum terbaca.');
    return next;
  }

  @override
  Future<ReceiptCapture?> recover() async => null;
}

class FailingRepository extends MemoryLedgerRepository {
  @override
  Future<void> save(LedgerEntry entry, {bool allowDuplicate = false}) async {
    throw Exception('disk full');
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  Future<void> open(
    WidgetTester tester,
    LedgerRepository repo,
    FakeReceipts receipts, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MoneyBookApp(repository: repo, receipts: receipts));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester t) async {
    await t.ensureVisible(find.byKey(const Key('save-entry')));
    await t.tap(find.byKey(const Key('save-entry')));
    await t.pumpAndSettle();
  }

  testWidgets('beranda kosong tanpa bisnis dan navigasi empat tab', (t) async {
    await open(t, MemoryLedgerRepository(), FakeReceipts());
    expect(find.text('MoneyBook'), findsOneWidget);
    expect(find.text('Bisnis'), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(t.takeException(), isNull);
  });
  testWidgets('pemasukan tersimpan dan saldo berubah', (t) async {
    final r = MemoryLedgerRepository();
    await open(t, r, FakeReceipts());
    await t.tap(find.byKey(const Key('add-income')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('amount')), '100000');
    await save(t);
    expect((await r.readAll()).single.kind, EntryKind.income);
    expect(LedgerSummary(await r.readAll()).balance, 100000);
    expect(find.text('Catatan berhasil disimpan.'), findsOneWidget);
  });
  testWidgets('nominal nol ditolak', (t) async {
    final r = MemoryLedgerRepository();
    await open(t, r, FakeReceipts());
    await t.tap(find.byKey(const Key('add-expense')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('amount')), '0');
    await save(t);
    expect(await r.readAll(), isEmpty);
    expect(
      find.text('Masukkan nominal Rp1 sampai Rp9 triliun.'),
      findsOneWidget,
    );
  });
  testWidgets('scan harus dikonfirmasi sebelum menjadi pengeluaran', (t) async {
    final r = MemoryLedgerRepository();
    final f = FakeReceipts()
      ..next = ReceiptCapture(
        parseReceipt('TOKO CONTOH\n23/10/2026\nTOTAL 42500'),
      );
    await open(t, r, f);
    await t.tap(find.text('Scan Nota').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('scan-camera')));
    await t.pumpAndSettle();
    expect(find.text('Periksa hasil nota'), findsOneWidget);
    expect(await r.readAll(), isEmpty);
    await save(t);
    expect((await r.readAll()).single.amount, 42500);
    expect((await r.readAll()).single.receiptHash, isNotNull);
  });
  testWidgets('pembatalan pemilih foto tidak membuat transaksi', (t) async {
    final r = MemoryLedgerRepository();
    await open(t, r, FakeReceipts());
    await t.tap(find.text('Scan Nota').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('scan-gallery')));
    await t.pumpAndSettle();
    expect(await r.readAll(), isEmpty);
    expect(find.byKey(const Key('scan-camera')), findsOneWidget);
  });
  testWidgets('OCR gagal menyediakan coba lagi dan input manual', (t) async {
    final f = FakeReceipts()..fail = true;
    await open(t, MemoryLedgerRepository(), f);
    await t.tap(find.text('Scan Nota').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('scan-camera')));
    await t.pumpAndSettle();
    expect(find.text('Teks belum terbaca.'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Catat pengeluaran secara manual'),
      200,
    );
    expect(find.text('Catat pengeluaran secara manual'), findsOneWidget);
  });
  testWidgets('simpan gagal tidak menampilkan sukses', (t) async {
    final r = FailingRepository();
    await open(t, r, FakeReceipts());
    await t.tap(find.byKey(const Key('add-expense')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('amount')), '25000');
    await save(t);
    expect(await r.readAll(), isEmpty);
    expect(
      find.text('Catatan belum tersimpan. Coba lagi; saldo belum berubah.'),
      findsOneWidget,
    );
    expect(find.text('Catatan berhasil disimpan.'), findsNothing);
  });
  testWidgets('tanggal OCR yang tidak terbaca wajib dipilih', (t) async {
    final r = MemoryLedgerRepository();
    final f = FakeReceipts()
      ..next = ReceiptCapture(parseReceipt('TOKO\nTOTAL 25000'));
    await open(t, r, f);
    await t.tap(find.text('Scan Nota').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('scan-camera')));
    await t.pumpAndSettle();
    await save(t);
    expect(await r.readAll(), isEmpty);
    expect(
      find.text('Tanggal belum terbaca. Pilih tanggal nota terlebih dahulu.'),
      findsOneWidget,
    );
  });
  testWidgets('edit dan hapus melalui riwayat mengubah rekap', (t) async {
    final r = MemoryLedgerRepository();
    await r.save(
      LedgerEntry(
        id: 'e',
        kind: EntryKind.expense,
        amount: 25000,
        category: 'Belanja',
        date: DateTime.now(),
        merchant: 'Toko Contoh',
      ),
    );
    await open(t, r, FakeReceipts());
    await t.tap(find.text('Riwayat').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Toko Contoh'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('amount')), '30000');
    await save(t);
    expect(LedgerSummary(await r.readAll()).expense, 30000);
    await t.tap(find.byTooltip('Pilihan catatan'));
    await t.pumpAndSettle();
    await t.tap(find.text('Hapus'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await t.pumpAndSettle();
    expect(await r.readAll(), isEmpty);
  });
  testWidgets('pencarian riwayat menyaring toko', (t) async {
    final r = MemoryLedgerRepository();
    await r.save(
      LedgerEntry(
        id: 'e',
        kind: EntryKind.expense,
        amount: 25000,
        category: 'Belanja',
        date: DateTime.now(),
        merchant: 'Toko Contoh',
      ),
    );
    await open(t, r, FakeReceipts());
    await t.tap(find.text('Riwayat').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('search')), 'tidakada');
    await t.pumpAndSettle();
    expect(find.text('Toko Contoh'), findsNothing);
    expect(find.text('0 catatan'), findsOneWidget);
    await t.enterText(find.byKey(const Key('search')), 'contoh');
    await t.pumpAndSettle();
    expect(find.text('Toko Contoh'), findsOneWidget);
  });
  testWidgets(
    'peringatan duplikat tidak menggandakan catatan tanpa persetujuan',
    (t) async {
      final r = MemoryLedgerRepository();
      final d = parseReceipt('TOKO\n23/10/2026\nTOTAL 25000');
      await r.save(
        LedgerEntry(
          id: 'e',
          kind: EntryKind.expense,
          amount: 25000,
          category: 'Belanja',
          date: DateTime.now(),
          receiptHash: d.hash,
        ),
      );
      final f = FakeReceipts()..next = ReceiptCapture(d);
      await open(t, r, f);
      await t.tap(find.text('Scan Nota').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('scan-camera')));
      await t.pumpAndSettle();
      await save(t);
      expect(find.text('Nota mungkin sudah dicatat'), findsOneWidget);
      expect((await r.readAll()).length, 1);
      await t.tap(find.text('Periksa kembali'));
      await t.pumpAndSettle();
      expect((await r.readAll()).length, 1);
    },
  );
  testWidgets('kembali dari form yang berubah meminta konfirmasi', (t) async {
    await open(t, MemoryLedgerRepository(), FakeReceipts());
    await t.tap(find.byKey(const Key('add-income')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('amount')), '25000');
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Keluar tanpa menyimpan?'), findsOneWidget);
    await t.tap(find.text('Lanjut isi'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('amount')), findsOneWidget);
  });
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets('empat tab tanpa overflow pada lebar $width', (t) async {
      await open(
        t,
        MemoryLedgerRepository(),
        FakeReceipts(),
        size: Size(width, 844),
      );
      for (final tab in ['Riwayat', 'Scan Nota', 'Rekap', 'Beranda']) {
        await t.tap(find.text(tab).last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
    });
  }
}
