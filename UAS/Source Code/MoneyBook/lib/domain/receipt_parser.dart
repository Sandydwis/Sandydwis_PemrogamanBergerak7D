import 'dart:convert';

import 'package:crypto/crypto.dart';

class ReceiptDraft {
  const ReceiptDraft({
    required this.rawText,
    required this.hash,
    this.merchant = '',
    this.amount,
    this.date,
    this.ambiguous = false,
  });
  final String rawText;
  final String hash;
  final String merchant;
  final int? amount;
  final DateTime? date;
  final bool ambiguous;
}

// Whole Indonesian rupiah only. Fractional values require manual confirmation.
int? parseReceiptAmount(String input) {
  var s = input
      .replaceAll(RegExp(r'(?i:rp)\.?'), '')
      .replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^\d[\d.,]*$').hasMatch(s)) return null;
  if (s.contains(',') && s.contains('.')) {
    final decimal = s.lastIndexOf(',') > s.lastIndexOf('.') ? ',' : '.';
    final split = s.split(decimal);
    if (split.last != '00' || split.length != 2) return null;
    s = split.first.replaceAll(RegExp(r'[.,]'), '');
  } else if (s.contains(',') || s.contains('.')) {
    final separator = s.contains(',') ? ',' : '.';
    final parts = s.split(separator);
    if (parts.length == 2 && parts.last == '00') {
      s = parts.first;
    } else if (parts.first.length <= 3 &&
        parts.skip(1).every((p) => p.length == 3)) {
      s = parts.join();
    } else {
      return null;
    }
  }
  final n = int.tryParse(s);
  return n != null && n > 0 && n <= 9000000000000 ? n : null;
}

DateTime? _validDate(int y, int m, int d) {
  if (y < 2000 || y > 2100) return null;
  final date = DateTime(y, m, d);
  return date.year == y && date.month == m && date.day == d ? date : null;
}

ReceiptDraft parseReceipt(String text) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  DateTime? date;
  for (final line in lines) {
    final iso = RegExp(r'\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b')
        .firstMatch(line);
    final local = RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})\b')
        .firstMatch(line);
    if (iso != null) {
      date = _validDate(
        int.parse(iso[1]!),
        int.parse(iso[2]!),
        int.parse(iso[3]!),
      );
    }
    if (date == null && local != null) {
      var y = int.parse(local[3]!);
      if (y < 100) y += 2000;
      date = _validDate(y, int.parse(local[2]!), int.parse(local[1]!));
    }
    if (date != null) break;
  }
  final candidates = <({int amount, int score})>[];
  final amountPattern = RegExp(r'(?:[Rr][Pp]\.?\s*)?\d[\d.,]*');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].toUpperCase();
    if (RegExp(
      r'SUB\s*TOTAL|TOTAL\s*(ITEM|QTY|BARANG)|KEMBALI|TUNAI|CASH|PAJAK|DISKON|DISCOUNT',
    ).hasMatch(line)) {
      continue;
    }
    final label = RegExp(
      r'GRAND\s*TOTAL|TOTAL\s*(BAYAR|BELANJA|PEMBAYARAN)|JUMLAH\s*(BAYAR|PEMBAYARAN)|\bTOTAL\b',
    ).firstMatch(line);
    if (label == null) continue;
    var remainder = line.substring(label.end);
    if (!RegExp(r'\d').hasMatch(remainder) &&
        i + 1 < lines.length &&
        RegExp(
          r'^(RP\.?\s*)?[\d.,\s]+$',
          caseSensitive: false,
        ).hasMatch(lines[i + 1])) {
      remainder = lines[i + 1];
    }
    final values = amountPattern
        .allMatches(remainder)
        .map((m) => parseReceiptAmount(m[0]!))
        .whereType<int>()
        .toSet();
    if (values.length != 1) continue;
    final score = label[0] == 'TOTAL' ? 1 : 2;
    candidates.add((amount: values.single, score: score));
  }
  final highest = candidates.isEmpty
      ? 0
      : candidates.map((c) => c.score).reduce((a, b) => a > b ? a : b);
  final totals = candidates
      .where((c) => c.score == highest)
      .map((c) => c.amount)
      .toSet();
  String merchant = '';
  for (final line in lines.take(4)) {
    if (line.length >= 3 &&
        line.length <= 100 &&
        RegExp(r'[a-zA-Z]{3}').hasMatch(line) &&
        !RegExp(
          r'^(jl\.?|jalan|tel|npwp|tanggal|nota|struk|receipt)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
      merchant = line;
      break;
    }
  }
  return ReceiptDraft(
    rawText: text,
    hash: sha256.convert(utf8.encode(normalized)).toString(),
    merchant: merchant,
    amount: totals.length == 1 ? totals.single : null,
    date: date,
    ambiguous: totals.length > 1,
  );
}
