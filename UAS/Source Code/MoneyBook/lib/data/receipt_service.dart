import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/receipt_parser.dart';

enum ReceiptSource { camera, gallery }

class ReceiptCapture {
  const ReceiptCapture(this.draft, {this.preview});
  final ReceiptDraft draft;
  final Uint8List? preview;
}

abstract class ReceiptService {
  Future<ReceiptCapture?> capture(ReceiptSource source);
  Future<ReceiptCapture?> recover();
}

class NativeReceiptService implements ReceiptService {
  final ImagePicker _picker = ImagePicker();
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<ReceiptCapture?> capture(ReceiptSource source) async {
    if (!_supported) {
      throw UnsupportedError(
        'Scan nota tersedia pada aplikasi Android. Gunakan catatan manual pada pratinjau browser.',
      );
    }
    final image = await _picker.pickImage(
      source: source == ReceiptSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2200,
      maxHeight: 2800,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    return image == null ? null : _recognize(image);
  }

  @override
  Future<ReceiptCapture?> recover() async {
    if (!_supported) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    return files == null || files.isEmpty ? null : _recognize(files.first);
  }

  Future<ReceiptCapture> _recognize(XFile image) async {
    if (await image.length() > 20 * 1024 * 1024) {
      throw const FormatException(
        'Ukuran gambar maksimal 20 MB. Pilih gambar yang lebih kecil.',
      );
    }
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      if (result.text.trim().isEmpty) {
        throw const FormatException(
          'Teks belum terbaca. Foto ulang dengan cahaya cukup atau catat manual.',
        );
      }
      return ReceiptCapture(
        parseReceipt(result.text),
        preview: await image.readAsBytes(),
      );
    } finally {
      await recognizer.close();
    }
  }
}
