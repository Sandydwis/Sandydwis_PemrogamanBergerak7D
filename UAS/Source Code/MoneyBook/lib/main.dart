import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/ledger_repository.dart';
import 'data/receipt_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  LedgerRepository? _repository;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _failed = false);
    try {
      final LedgerRepository repo = kIsWeb
          ? MemoryLedgerRepository()
          : await SqliteLedgerRepository.open();
      if (mounted) {
        setState(() => _repository = repo);
      } else {
        await repo.close();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _repository?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repository;
    if (repo != null) {
      return MoneyBookApp(
        repository: repo,
        receipts: NativeReceiptService(),
        preview: kIsWeb,
      );
    }
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Penyimpanan belum dapat dibuka. Data tidak dihapus.',
                    ),
                    FilledButton(
                      onPressed: _open,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
