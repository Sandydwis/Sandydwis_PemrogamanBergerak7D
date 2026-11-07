import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'data/ledger_repository.dart';
import 'data/receipt_service.dart';
import 'domain/ledger.dart';

const navy = Color(0xFF142B45);
const teal = Color(0xFF087F75);
const muted = Color(0xFF556577);
const paper = Color(0xFFF3F6FA);
String money(int v) => NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp',
  decimalDigits: 0,
).format(v);
String dateLabel(DateTime d) => DateFormat('d MMM yyyy', 'id_ID').format(d);
String monthLabel(DateTime d) => DateFormat('MMMM yyyy', 'id_ID').format(d);

class MoneyBookApp extends StatelessWidget {
  const MoneyBookApp({
    super.key,
    required this.repository,
    required this.receipts,
    this.preview = false,
  });
  final LedgerRepository repository;
  final ReceiptService receipts;
  final bool preview;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MoneyBook',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'MoneySans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: navy,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          color: navy,
          fontSize: 28,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          color: navy,
          fontSize: 20,
        ),
        bodyMedium: TextStyle(color: navy, fontSize: 14, height: 1.45),
      ),
    ),
    home: LedgerHome(
      repository: repository,
      receipts: receipts,
      preview: preview,
    ),
  );
}

class LedgerHome extends StatefulWidget {
  const LedgerHome({
    super.key,
    required this.repository,
    required this.receipts,
    required this.preview,
  });
  final LedgerRepository repository;
  final ReceiptService receipts;
  final bool preview;
  @override
  State<LedgerHome> createState() => _LedgerHomeState();
}

class _LedgerHomeState extends State<LedgerHome> {
  List<LedgerEntry> _entries = [];
  bool _loading = true;
  String? _error;
  int _tab = 0;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  EntryKind? _kind;
  String _search = '';
  bool _scanning = false;
  String? _scanError;
  ReceiptSource _lastSource = ReceiptSource.camera;

  @override
  void initState() {
    super.initState();
    _reload();
    _recover();
  }

  Future<void> _reload() async {
    try {
      final values = await widget.repository.readAll();
      if (mounted) {
        setState(() {
          _entries = values;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Catatan belum dapat dibaca. Coba lagi; data tidak dihapus.';
        });
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _recover() async {
    try {
      final capture = await widget.receipts.recover();
      if (capture == null || !mounted) return;
      if (_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _edit(capture: capture);
        });
      } else {
        await _edit(capture: capture);
      }
    } catch (_) {
      _message(
        'Pemulihan foto belum berhasil. Buka Scan Nota untuk memilih ulang.',
      );
    }
  }

  Future<void> _edit({
    EntryKind kind = EntryKind.expense,
    LedgerEntry? existing,
    ReceiptCapture? capture,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntryEditor(
          repository: widget.repository,
          kind: existing?.kind ?? kind,
          existing: existing,
          capture: capture,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _reload();
      _message(
        existing == null
            ? 'Catatan berhasil disimpan.'
            : 'Perubahan berhasil disimpan.',
      );
    }
  }

  Future<void> _scan(ReceiptSource source) async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanError = null;
      _lastSource = source;
    });
    try {
      final capture = await widget.receipts.capture(source);
      if (!mounted) return;
      setState(() => _scanning = false);
      if (capture != null) await _edit(capture: capture);
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanError = error is FormatException ? error.message : 'Foto belum dapat diproses. Periksa akses kamera/foto, lalu coba lagi atau catat manual.';
        });
      }
    }
  }

  Future<void> _delete(LedgerEntry entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus catatan?'),
        content: Text(
          '${money(entry.amount)} • ${entry.category}\nRekap akan dihitung ulang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.repository.delete(entry.id);
      await _reload();
      _message('Catatan dihapus.');
    } catch (_) {
      _message('Catatan belum terhapus. Coba lagi.');
    }
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tentang catatanmu',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'MoneyBook menyimpan catatan pribadi di perangkat. Saldo berasal dari pemasukan dikurangi pengeluaran yang kamu catat. Tidak ada koneksi rekening atau fitur transfer uang.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Foto nota hanya dipakai untuk membaca teks dan pratinjau. Foto dan teks OCR lengkap tidak disimpan dalam database. Data transaksi belum dienkripsi oleh aplikasi; gunakan kunci layar perangkat. Menghapus aplikasi juga dapat menghapus catatan.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: exportJson(_entries)),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _message(
                    'Salinan JSON seluruh catatan ada di clipboard. Simpan ke berkas pribadi.',
                  );
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Salin seluruh data (JSON)'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  final yes = await showDialog<bool>(
                    context: ctx,
                    builder: (d) => AlertDialog(
                      title: const Text('Hapus semua catatan?'),
                      content: const Text(
                        'Tindakan ini tidak dapat dibatalkan. Salin data terlebih dahulu bila masih diperlukan.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('Batal'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('Hapus semua'),
                        ),
                      ],
                    ),
                  );
                  if (yes != true) return;
                  try {
                    await widget.repository.clear();
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _reload();
                    _message('Semua catatan dihapus.');
                  } catch (_) {
                    _message('Data belum dihapus. Coba lagi.');
                  }
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text(
                  'Hapus semua data',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child, {Color color = Colors.white}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
    ),
    child: child,
  );
  Widget _title(String t) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 12),
    child: Text(t, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget _empty(String title, String detail, IconData icon) => _card(
    Column(
      children: [
        Icon(icon, size: 40, color: teal),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
      ],
    ),
  );
  Widget _entry(LedgerEntry e) => Card(
    elevation: 0,
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 5, 4, 5),
      leading: CircleAvatar(
        backgroundColor: e.kind == EntryKind.income
            ? const Color(0xFFE4F3EE)
            : const Color(0xFFFFEEE7),
        child: Icon(
          e.kind == EntryKind.income ? Icons.south_west : Icons.north_east,
          color: e.kind == EntryKind.income ? teal : const Color(0xFFB64C26),
        ),
      ),
      title: Text(
        e.merchant.isEmpty ? e.category : e.merchant,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${dateLabel(e.date)} • ${e.category}${e.receiptHash != null ? ' • Nota' : ''}',
        maxLines: 2,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${e.kind == EntryKind.income ? '+' : '−'}${money(e.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: e.kind == EntryKind.income ? teal : navy,
              fontSize: 12,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Pilihan catatan',
            onSelected: (v) {
              if (v == 'edit') {
                _edit(existing: e);
              } else {
                _delete(e);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Hapus')),
            ],
          ),
        ],
      ),
      onTap: () => _edit(existing: e),
    ),
  );
  Widget _period() => Row(
    children: [
      IconButton(
        tooltip: 'Bulan sebelumnya',
        onPressed: _month.year <= 2000 && _month.month == 1
            ? null
            : () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Text(
          monthLabel(_month),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      IconButton(
        tooltip: 'Bulan berikutnya',
        onPressed: _month.year >= 2100 && _month.month == 12
            ? null
            : () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  Widget _metric(String label, int value, Color color) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          money(value),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ],
    ),
  );
  List<Widget> _dashboard() {
    final all = LedgerSummary(_entries);
    final period = LedgerSummary(filterEntries(_entries, month: _month));
    return [
      const Text(
        'Catat hari ini,\npahami uangmu.',
        style: TextStyle(
          fontSize: 29,
          height: 1.15,
          fontWeight: FontWeight.w800,
          color: navy,
        ),
      ),
      const SizedBox(height: 20),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saldo tercatat • seluruh waktu',
              style: TextStyle(color: Color(0xFFBFD7E0)),
            ),
            const SizedBox(height: 10),
            Text(
              money(all.balance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Pemasukan dikurangi pengeluaran',
              style: TextStyle(color: Color(0xFFBFD7E0), fontSize: 12),
            ),
          ],
        ),
        color: navy,
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            key: const Key('add-income'),
            onPressed: () => _edit(kind: EntryKind.income),
            icon: const Icon(Icons.add),
            label: const Text('Pemasukan'),
          ),
          OutlinedButton.icon(
            key: const Key('add-expense'),
            onPressed: () => _edit(),
            icon: const Icon(Icons.remove),
            label: const Text('Pengeluaran'),
          ),
        ],
      ),
      _title('Ringkasan bulan ini'),
      _period(),
      const SizedBox(height: 10),
      _card(
        Row(
          children: [
            _metric('Pemasukan', period.income, teal),
            _metric('Pengeluaran', period.expense, const Color(0xFFB64C26)),
          ],
        ),
      ),
      _title('Catatan terbaru'),
      if (_entries.isEmpty)
        _empty(
          'Mulai dari satu catatan',
          'Tambahkan pemasukan atau pindai nota belanja pertamamu.',
          Icons.receipt_long_outlined,
        )
      else
        ..._entries.take(5).map(_entry),
      TextButton(
        onPressed: () => setState(() => _tab = 1),
        child: const Text('Lihat seluruh riwayat'),
      ),
    ];
  }

  List<Widget> _history() {
    final list = filterEntries(
      _entries,
      month: _month,
      kind: _kind,
      search: _search,
    );
    return [
      _period(),
      const SizedBox(height: 12),
      TextField(
        key: const Key('search'),
        decoration: const InputDecoration(
          hintText: 'Cari toko, kategori, atau catatan',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Semua'),
            selected: _kind == null,
            onSelected: (_) => setState(() => _kind = null),
          ),
          ...EntryKind.values.map(
            (k) => ChoiceChip(
              label: Text(k == EntryKind.income ? 'Pemasukan' : 'Pengeluaran'),
              selected: _kind == k,
              onSelected: (_) => setState(() => _kind = k),
            ),
          ),
        ],
      ),
      _title('${list.length} catatan'),
      if (list.isEmpty)
        _empty(
          'Belum ada catatan yang cocok',
          'Ubah bulan atau kata pencarian, atau tambahkan transaksi.',
          Icons.manage_search,
        )
      else
        ...list.map(_entry),
      FilledButton.icon(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah pengeluaran'),
      ),
    ];
  }

  List<Widget> _scanView() => [
    _card(
      Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: const Color(0xFFE4F3EE),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.document_scanner_outlined,
              size: 42,
              color: teal,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Nota jadi catatan',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text(
            'Ambil foto yang terang dan tidak terpotong. Periksa hasil pembacaan sebelum menyimpan pengeluaran.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('scan-camera'),
            onPressed: _scanning ? null : () => _scan(ReceiptSource.camera),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Foto nota'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('scan-gallery'),
            onPressed: _scanning ? null : () => _scan(ReceiptSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Pilih dari galeri'),
          ),
          if (_scanning) ...[
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            const Text('Membaca teks pada nota…'),
          ],
        ],
      ),
    ),
    const SizedBox(height: 16),
    if (_scanError != null)
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_scanError!, style: const TextStyle(color: Color(0xFFAA381D))),
            TextButton(
              onPressed: () => _scan(_lastSource),
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    _title('Tiga langkah sederhana'),
    const Text(
      '1. Foto atau pilih gambar nota.\n2. Periksa total, tanggal, toko, dan kategori.\n3. Simpan satu nota sebagai satu pengeluaran.',
      style: TextStyle(height: 1.9),
    ),
    const SizedBox(height: 12),
    const Text(
      'Foto diproses pada perangkat dan tidak disimpan sebagai lampiran transaksi.',
      style: TextStyle(color: muted, fontSize: 12),
    ),
    TextButton(
      onPressed: _scanning ? null : () => _edit(),
      child: const Text('Catat pengeluaran secara manual'),
    ),
  ];
  List<Widget> _reports() {
    final list = filterEntries(_entries, month: _month);
    final s = LedgerSummary(list);
    final cats = s.categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      _period(),
      const SizedBox(height: 12),
      _card(
        Column(
          children: [
            Row(
              children: [
                _metric('Pemasukan', s.income, teal),
                _metric('Pengeluaran', s.expense, const Color(0xFFB64C26)),
              ],
            ),
            const Divider(height: 30),
            Row(
              children: [
                const Expanded(child: Text('Selisih periode')),
                Text(
                  money(s.balance),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      _title('Pengeluaran per kategori'),
      if (cats.isEmpty)
        _empty(
          'Belum ada pengeluaran',
          'Rekap akan terisi dari transaksi pada bulan yang dipilih.',
          Icons.pie_chart_outline,
        )
      else
        _card(
          Column(
            children: cats
                .map(
                  (cat) => Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(cat.key)),
                            Text(
                              money(cat.value),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          label:
                              '${cat.key}: ${(100 * cat.value / s.expense).round()} persen',
                          child: LinearProgressIndicator(
                            value: cat.value / s.expense,
                            minHeight: 9,
                            borderRadius: BorderRadius.circular(8),
                            backgroundColor: paper,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: list.isEmpty
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: exportCsv(list)));
                _message(
                  'CSV periode ini disalin. Tempel dan simpan sebagai berkas CSV.',
                );
              },
        icon: const Icon(Icons.copy_outlined),
        label: const Text('Salin rekap CSV'),
      ),
      const SizedBox(height: 10),
      const Text(
        'Rekap mengikuti tanggal transaksi. Saldo di Beranda mencakup seluruh waktu.',
        style: TextStyle(fontSize: 12, color: muted),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['MoneyBook', 'Riwayat', 'Scan Nota', 'Rekap'];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[_tab],
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Pengaturan data',
            onPressed: _loading || _error != null ? null : _settings,
            icon: const Icon(Icons.tune_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              )
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    key: ValueKey('tab-$_tab'),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      if (widget.preview) ...[
                        const MaterialBanner(
                          content: Text(
                            'Pratinjau browser: data sementara, scan kamera tersedia di Android.',
                          ),
                          actions: [SizedBox.shrink()],
                        ),
                        const SizedBox(height: 12),
                      ],
                      ...switch (_tab) {
                        0 => _dashboard(),
                        1 => _history(),
                        2 => _scanView(),
                        _ => _reports(),
                      },
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          if (!_scanning) setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Riwayat',
          ),
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            label: 'Scan Nota',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Rekap',
          ),
        ],
      ),
    );
  }
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({
    super.key,
    required this.repository,
    required this.kind,
    this.existing,
    this.capture,
  });
  final LedgerRepository repository;
  final EntryKind kind;
  final LedgerEntry? existing;
  final ReceiptCapture? capture;
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount, _note, _merchant;
  late String _category;
  late DateTime _date;
  late final String _id;
  bool _saving = false;
  bool _dateConfirmed = true;
  bool _dirty = false;
  bool get _isIncome => widget.kind == EntryKind.income;
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final d = widget.capture?.draft;
    _id = e?.id ?? const Uuid().v4();
    _amount = TextEditingController(
      text: e != null ? '${e.amount}' : d?.amount?.toString() ?? '',
    );
    _note = TextEditingController(text: e?.note ?? '');
    _merchant = TextEditingController(text: e?.merchant ?? d?.merchant ?? '');
    _category =
        e?.category ??
        (_isIncome ? incomeCategories.first : expenseCategories.first);
    _date = e?.date ?? d?.date ?? DateTime.now();
    _dateConfirmed = d == null || d.date != null;
    for (final t in [_amount, _note, _merchant]) {
      t.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _merchant.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (d != null && mounted) {
      setState(() {
        _date = d;
        _dateConfirmed = true;
        _dirty = true;
      });
    }
  }

  Future<void> _save({bool allowDuplicate = false}) async {
    if (_saving || !_form.currentState!.validate()) return;
    if (!_dateConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tanggal belum terbaca. Pilih tanggal nota terlebih dahulu.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final e = LedgerEntry(
      id: _id,
      kind: widget.kind,
      amount: int.parse(_amount.text),
      category: _category,
      date: _date,
      note: _note.text.trim(),
      merchant: _merchant.text.trim(),
      receiptHash: widget.existing?.receiptHash ?? widget.capture?.draft.hash,
    );
    try {
      await widget.repository.save(e, allowDuplicate: allowDuplicate);
      if (mounted) {
        _dirty = false;
        Navigator.of(context).pop(true);
      }
    } on DuplicateReceipt {
      if (!mounted) return;
      setState(() => _saving = false);
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Nota mungkin sudah dicatat'),
          content: const Text(
            'Hasil pembacaan nota ini sama dengan catatan sebelumnya. Simpan lagi hanya jika memang transaksi yang berbeda.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Periksa kembali'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tetap simpan'),
            ),
          ],
        ),
      );
      if (yes == true && mounted) await _save(allowDuplicate: true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'Catatan belum tersimpan. Coba lagi; saldo belum berubah.',
            ),
          ),
        );
      }
    }
  }

  Future<bool> _leave() async {
    if (_saving) return false;
    if (!_dirty && widget.capture == null) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Keluar tanpa menyimpan?'),
            content: const Text(
              'Perubahan pada formulir ini belum menjadi catatan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Lanjut isi'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Keluar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.capture?.draft;
    final Uint8List? image = widget.capture?.preview;
    return PopScope(
      canPop: !_dirty && widget.capture == null && !_saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _leave() && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            d != null
                ? 'Periksa hasil nota'
                : widget.existing != null
                ? 'Edit catatan'
                : _isIncome
                ? 'Tambah pemasukan'
                : 'Tambah pengeluaran',
          ),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (d != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE4F3EE),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            d.amount == null
                                ? 'Total belum terbaca dengan pasti. Masukkan nominal yang benar dari nota.'
                                : 'Periksa kembali total, tanggal, toko, dan kategori. Catatan baru dibuat setelah kamu menekan Simpan.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (image != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              image,
                              height: 160,
                              fit: BoxFit.contain,
                              errorBuilder: (_, error, stack) => const Text(
                                'Pratinjau gambar tidak tersedia.',
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        key: const Key('amount'),
                        controller: _amount,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Nominal (Rp)',
                          hintText: 'Contoh: 25000',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return n == null || n <= 0 || n > 9000000000000
                              ? 'Masukkan nominal Rp1 sampai Rp9 triliun.'
                              : null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: const Key('category'),
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Kategori',
                        ),
                        items:
                            (_isIncome ? incomeCategories : expenseCategories)
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() {
                                _category = v!;
                                _dirty = true;
                              }),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        key: const Key('date'),
                        onPressed: _saving ? null : _pickDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          _dateConfirmed
                              ? dateLabel(_date)
                              : 'Pilih tanggal nota (belum terbaca)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('merchant'),
                        controller: _merchant,
                        enabled: !_saving,
                        maxLength: 100,
                        decoration: InputDecoration(
                          labelText: _isIncome
                              ? 'Sumber / pemberi (opsional)'
                              : 'Nama toko (opsional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        key: const Key('note'),
                        controller: _note,
                        enabled: !_saving,
                        maxLength: 500,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Catatan (opsional)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (d != null) ...[
                        ExpansionTile(
                          title: const Text('Lihat teks yang terbaca'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(d.rawText),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      FilledButton.icon(
                        key: const Key('save-entry'),
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(_saving ? 'Menyimpan…' : 'Simpan catatan'),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
