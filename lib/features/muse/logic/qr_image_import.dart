// 穿云 1.14.0 R11 - 从相册识别二维码: the system picker hands over one image (no storage
// permission is asked for: Android's picker grants access to the chosen picture only), the
// scanner already in the app reads the code from it, and the copy the picker made is removed.
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

enum MuseQrImageOutcome { cancelled, found, notFound, failed }

class MuseQrImageResult {
  const MuseQrImageResult(this.outcome, [this.text]);

  final MuseQrImageOutcome outcome;
  final String? text;

  /// What the scanner page says when nothing could be imported (null = nothing to say).
  String? get message => switch (outcome) {
    MuseQrImageOutcome.notFound => '这张图片里没有找到二维码，换一张清晰的截图试试',
    MuseQrImageOutcome.failed => '读取图片失败，请换一张图片',
    _ => null,
  };
}

/// Picks an image; returns its path (null = the user closed the picker).
typedef MusePickImage = Future<String?> Function();

/// Reads a QR code in the image at a path; returns its text (null = none found).
typedef MuseDecodeImage = Future<String?> Function(String path);

Future<MuseQrImageResult> museScanQrFromImage({MusePickImage? pick, MuseDecodeImage? decode, bool deleteAfter = true}) async {
  final String? path;
  try {
    path = await (pick ?? museSystemPickImage)();
  } catch (_) {
    return const MuseQrImageResult(MuseQrImageOutcome.failed);
  }
  if (path == null || path.isEmpty) return const MuseQrImageResult(MuseQrImageOutcome.cancelled);
  try {
    final text = (await (decode ?? museDecodeQrImage)(path))?.trim();
    if (text == null || text.isEmpty) return const MuseQrImageResult(MuseQrImageOutcome.notFound);
    return MuseQrImageResult(MuseQrImageOutcome.found, text);
  } catch (_) {
    return const MuseQrImageResult(MuseQrImageOutcome.failed);
  } finally {
    if (deleteAfter) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

/// The system image picker (a copy in the app's cache; not compressed, so small codes stay readable).
Future<String?> museSystemPickImage() async {
  final r = await FilePicker.platform.pickFiles(type: FileType.image, compressionQuality: 0);
  return r?.files.single.path;
}

/// The camera scanner's own decoder, run on a file. Called on the platform directly: a throwaway
/// controller's dispose would also stop the live camera preview behind the button.
Future<String?> museDecodeQrImage(String path) async {
  final capture = await MobileScannerPlatform.instance.analyzeImage(path, formats: const [BarcodeFormat.qrCode]);
  for (final b in capture?.barcodes ?? const <Barcode>[]) {
    final v = b.rawValue;
    if (v != null && v.trim().isNotEmpty) return v;
  }
  return null;
}
