import 'dart:convert';

enum EntryKind { income, expense }

const expenseCategories = [
  'Makan & Minum',
  'Belanja',
  'Transportasi',
  'Tagihan',
  'Kesehatan',
  'Pendidikan',
  'Hiburan',
  'Lainnya',
];
const incomeCategories = ['Gaji', 'Uang Saku', 'Hadiah', 'Lainnya'];

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.category,
    required this.date,
    this.note = '',
    this.merchant = '',
    this.receiptHash,
  });
  final String id;
  final EntryKind kind;
  final int amount;
  final String category;
  final DateTime date;
  final String note;
  final String merchant;
  final String? receiptHash;

  void validate() {
    if (id.isEmpty || amount <= 0 || amount > 9000000000000) {
      throw const FormatException(
        'Nominal harus Rp1 sampai Rp9.000.000.000.000.',
      );
    }
    if (!(kind == EntryKind.income ? incomeCategories : expenseCategories)
        .contains(category)) {
      throw const FormatException('Pilih kategori yang sesuai.');
    }
    if (date.year < 2000 || date.year > 2100) {
      throw const FormatException('Tanggal tidak valid.');
    }
    if (note.length > 500 || merchant.length > 100) {
      throw const FormatException('Keterangan terlalu panjang.');
    }
    if (receiptHash != null &&
        (kind != EntryKind.expense ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(receiptHash!))) {
      throw const FormatException('Referensi nota tidak valid.');
    }
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind.name,
    'amount': amount,
    'category': category,
    'date': dayKey(date),
    'note': note.trim(),
    'merchant': merchant.trim(),
    'receipt_hash': receiptHash,
  };
  factory LedgerEntry.fromMap(Map<String, Object?> m) => LedgerEntry(
    id: m['id'] as String,
    kind: EntryKind.values.byName(m['kind'] as String),
    amount: m['amount'] as int,
    category: m['category'] as String,
    date: DateTime.parse(m['date'] as String),
    note: m['note'] as String,
    merchant: m['merchant'] as String,
    receiptHash: m['receipt_hash'] as String?,
  );
}

class LedgerSummary {
  LedgerSummary(Iterable<LedgerEntry> entries) {
    for (final e in entries) {
      if (e.kind == EntryKind.income) {
        income += e.amount;
      } else {
        expense += e.amount;
        categories.update(
          e.category,
          (v) => v + e.amount,
          ifAbsent: () => e.amount,
        );
      }
    }
  }
  int income = 0;
  int expense = 0;
  int get balance => income - expense;
  final Map<String, int> categories = {};
}

List<LedgerEntry> filterEntries(
  Iterable<LedgerEntry> entries, {
  DateTime? month,
  EntryKind? kind,
  String search = '',
}) {
  final q = search.trim().toLowerCase();
  return entries
      .where(
        (e) =>
            (month == null ||
                (e.date.year == month.year && e.date.month == month.month)) &&
            (kind == null || e.kind == kind) &&
            (q.isEmpty ||
                '${e.category} ${e.note} ${e.merchant}'.toLowerCase().contains(
                  q,
                )),
      )
      .toList();
}

String exportCsv(Iterable<LedgerEntry> entries) {
  String cell(Object? s) => '"${'$s'.replaceAll('"', '""')}"';
  // Prefix text fields that could be interpreted as spreadsheet formulas.
  String safe(String s) => RegExp(r'^[=+@\-\t\r]').hasMatch(s) ? "'$s" : s;
  return [
    'tanggal,jenis,kategori,nominal,toko,catatan',
    ...entries.map(
      (e) => [
        dayKey(e.date),
        e.kind.name,
        safe(e.category),
        e.amount,
        safe(e.merchant),
        safe(e.note),
      ].map(cell).join(','),
    ),
  ].join('\r\n');
}

String exportJson(Iterable<LedgerEntry> entries) =>
    const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'application': 'MoneyBook Personal',
      'entries': entries.map((e) => e.toMap()).toList(),
    });
