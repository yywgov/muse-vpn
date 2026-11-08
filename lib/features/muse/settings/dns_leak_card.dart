// 穿云 1.15.0 R20 - 诊断里的「DNS 泄漏检测」：点按「开始检测」才发一次请求，结果与失败都用中文显示。
// Part of 穿云 (GPLv3).

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/muse/data/port_override.dart';
import 'package:hiddify/features/muse/logic/dns_leak.dart';
import 'package:hiddify/features/muse/widget/grouped_list.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MuseDnsLeakCard extends HookConsumerWidget {
  const MuseDnsLeakCard({super.key, this.run});

  /// tests: replaces the network test
  final Future<MuseDnsLeakResult> Function()? run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = useState(false);
    final result = useState<MuseDnsLeakResult?>(null);
    final mounted = useIsMounted();
    final r = result.value;
    final (IconData icon, Color color) = switch (r?.verdict) {
      MuseDnsLeakVerdict.safe => (Icons.verified_user_outlined, MusePalette.green),
      MuseDnsLeakVerdict.leak => (Icons.report_outlined, MusePalette.orange),
      _ => (Icons.dns_outlined, Theme.of(context).colorScheme.onSurfaceVariant),
    };

    Future<void> start() async {
      busy.value = true;
      final res = await (run?.call() ??
          museRunDnsLeakTest(port: museEffectiveMixedPort(ref.read), connected: ref.read(serviceRunningProvider)));
      if (!mounted()) return;
      result.value = res;
      busy.value = false;
    }

    return Column(
      key: const ValueKey('dns_leak_card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: MuseIconSize.small),
            const SizedBox(width: MuseSpace.s8),
            Expanded(
              child: Text(
                r == null ? 'DNS 泄漏检测' : 'DNS 泄漏检测：${r.verdict.title}',
                style: MuseType.body(context).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              key: const ValueKey('dns_leak_start'),
              onPressed: busy.value ? null : start,
              child: Text(busy.value ? '检测中…' : (r == null ? '开始检测' : '重新检测')),
            ),
          ],
        ),
        Text(
          r?.text ?? '检查境外域名是不是由国内 DNS 解析（会访问公开检测服务 ip-api.com 一次）',
          key: const ValueKey('dns_leak_text'),
          style: MuseType.caption(context).copyWith(color: r?.failed ?? false ? Theme.of(context).colorScheme.error : null),
        ),
      ],
    );
  }
}
