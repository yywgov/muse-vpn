// 穿云 1.4.0 - a QR code drawn from the qr package (no image assets, no network).
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:qr/qr.dart';

class MuseQrView extends StatelessWidget {
  const MuseQrView(this.data, {super.key, this.size = MuseSize.qrCode});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    QrImage? image;
    try {
      image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
    } catch (_) {
      image = null;
    }
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(MuseSpace.s12),
      decoration: const BoxDecoration(color: MusePalette.white, borderRadius: MuseRadius.smallAll),
      child: image == null
          ? const Center(child: Text('内容太长，无法生成二维码'))
          : CustomPaint(key: const ValueKey('muse_qr'), painter: _QrPainter(image)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.shortestSide / n;
    final paint = Paint()..color = MusePalette.qrInk;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (image.isDark(y, x)) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.3, cell + 0.3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}

/// A dialog with the QR code of [data] and a 复制 button.
Future<void> showMuseQrDialog(BuildContext context, {required String title, required String data, String? copyText}) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [MuseQrView(data)]),
        actions: [
          TextButton(
            key: const ValueKey('qr_copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: copyText ?? data));
              if (c.mounted) Navigator.of(c).pop();
            },
            child: const Text('复制链接'),
          ),
          FilledButton(onPressed: () => Navigator.of(c).pop(), child: const Text('关闭')),
        ],
      ),
    );
