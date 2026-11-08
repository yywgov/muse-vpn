// 穿云 1.4.0 - a QR code drawn from the qr package (no image assets, no network).
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/data/secure_screen.dart';
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

/// 1.14.0 B5: what a shared QR code gives away, shown before it is drawn.
const museQrNodeWarning = '二维码里含有这个节点的地址、端口和密码等连接信息，任何人扫一下就能直接使用。只分享给信任的人，不要发到群里或公开的地方。';
const museQrSubscriptionWarning = '二维码里含有你的订阅链接（带订阅密钥），任何人扫一下就能导入并使用你的流量。只分享给信任的人，不要发到群里或公开的地方。';

/// Asks before a QR code with connection secrets is shown; true = the user chose 继续分享.
Future<bool> museConfirmSensitiveShare(BuildContext context, {required String warning}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const ValueKey('qr_sensitive_dialog'),
        title: const Text('含有敏感信息'),
        content: Text(warning),
        actions: [
          TextButton(key: const ValueKey('qr_sensitive_cancel'), onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
          FilledButton(key: const ValueKey('qr_sensitive_ok'), onPressed: () => Navigator.of(c).pop(true), child: const Text('继续分享')),
        ],
      ),
    ) ??
    false;

/// A dialog with the QR code of [data] and a 复制 button.
/// 1.14.0 B5: with a [warning] (node / subscription secrets) the user confirms first, and the
/// warning stays under the code.
Future<void> showMuseQrDialog(BuildContext context, {required String title, required String data, String? copyText, String? warning}) async {
  if (warning != null) {
    if (!await museConfirmSensitiveShare(context, warning: warning)) return;
    if (!context.mounted) return;
  }
  // 1.16.0 B8: no screenshots of a QR code while it is shown
  await museSecureFor(context, () => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MuseQrView(data),
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(top: MuseSpace.s12),
              child: SizedBox(
                width: MuseSize.qrCode,
                child: Text('仅分享给信任的人：扫码即可使用', key: const ValueKey('qr_sensitive_note'), textAlign: TextAlign.center, style: Theme.of(c).textTheme.bodySmall),
              ),
            ),
        ],
      ),
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
  ));
}
