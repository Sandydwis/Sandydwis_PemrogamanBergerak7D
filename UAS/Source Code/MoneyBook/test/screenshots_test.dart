import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:moneybook_personal/app.dart';
import 'package:moneybook_personal/data/ledger_repository.dart';
import 'package:moneybook_personal/data/receipt_service.dart';
import 'package:moneybook_personal/domain/ledger.dart';
import 'package:moneybook_personal/domain/receipt_parser.dart';

class ScreenshotReceipts implements ReceiptService {
  @override
  Future<ReceiptCapture?> capture(ReceiptSource source) async => ReceiptCapture(
    parseReceipt(
      'TOKO CONTOH\n23/10/2026\nMakanan 25.000\nMinuman 7.500\nTOTAL 32.500\nTUNAI 50.000\nKEMBALI 17.500',
    ),
  );
  @override
  Future<ReceiptCapture?> recover() async => null;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    final loader = FontLoader('MoneySans')
      ..addFont(rootBundle.load('assets/fonts/DejaVuSans.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets('render layar antarmuka dengan data contoh', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MemoryLedgerRepository();
    final now = DateTime.now();
    for (final e in [
      LedgerEntry(
        id: 'demo-1',
        kind: EntryKind.income,
        amount: 2500000,
        category: 'Gaji',
        date: now,
        note: 'Data contoh untuk pratinjau',
      ),
      LedgerEntry(
        id: 'demo-2',
        kind: EntryKind.expense,
        amount: 125000,
        category: 'Belanja',
        date: now,
        merchant: 'Toko Contoh',
      ),
      LedgerEntry(
        id: 'demo-3',
        kind: EntryKind.expense,
        amount: 32500,
        category: 'Makan & Minum',
        date: now,
        merchant: 'Kedai Contoh',
      ),
      LedgerEntry(
        id: 'demo-4',
        kind: EntryKind.expense,
        amount: 20000,
        category: 'Transportasi',
        date: now,
        note: 'Data contoh',
      ),
    ]) {
      await repo.save(e);
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('capture'),
        child: MoneyBookApp(repository: repo, receipts: ScreenshotReceipts()),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold).last))
          .clearSnackBars();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final d = Directory('../uts-uiux/screenshots');
        await d.create(recursive: true);
        await File('${d.path}/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('01-beranda');
    await tester.tap(find.text('Riwayat').last);
    await tester.pumpAndSettle();
    await capture('02-riwayat');
    await tester.tap(find.text('Scan Nota').last);
    await tester.pumpAndSettle();
    await capture('03-scan-nota');
    await tester.tap(find.byKey(const Key('scan-camera')));
    await tester.pumpAndSettle();
    await capture('04-konfirmasi-nota');
    await tester.ensureVisible(find.byKey(const Key('save-entry')));
    await tester.tap(find.byKey(const Key('save-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rekap').last);
    await tester.pumpAndSettle();
    await capture('05-rekap');
    await tester.tap(find.text('Beranda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-income')));
    await tester.pumpAndSettle();
    await capture('06-form-manual');
  });
}
