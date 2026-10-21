// 穿云 1.2.8
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/muse/model/route_mode.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';

void main() {
  group('tray icon / tooltip', () {
    test('icon is blue (Connected) as soon as connected, delay or not', () {
      expect(museTrayIconStatus(const Connected()), isA<Connected>());
      expect(museTrayIconStatus(const Connecting()), isA<Connecting>());
      expect(museTrayIconStatus(const Disconnected()), isA<Disconnected>());
    });
    test('delay and speed only go into the tooltip', () {
      expect(museTrayTooltip(const Connected(), 0, '已连接'), '穿云 - 已连接');
      expect(museTrayTooltip(const Connected(), 123, '已连接'), '穿云 - 已连接 · 123ms');
      expect(museTrayTooltip(const Connected(), 65535, '已连接', speed: '↓1 KB/s ↑0 B/s'), '穿云 - 已连接 · ↓1 KB/s ↑0 B/s');
      expect(museTrayTooltip(const Disconnected(), 123, '未连接', speed: 'x'), '穿云 - 未连接');
    });
    test('tray menu shows the speed while connected', () {
      final on = museTrayMenuSpec(const Connected(), MuseRouteMode.rule, speed: '↓2 KB/s ↑1 KB/s');
      expect(on.first.key, 'speed');
      expect(on.first.disabled, isTrue);
      expect(on[1].label, '断开');
      final off = museTrayMenuSpec(const Disconnected(), MuseRouteMode.rule, speed: '↓2 KB/s ↑1 KB/s');
      expect(off.first.label, '连接');
      expect(museSpeedText(1024, 2048), '↓2 KB/s ↑1 KB/s');
    });
  });
}
