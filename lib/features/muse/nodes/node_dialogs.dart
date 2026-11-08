// 穿云 - node list: small dialogs and widgets (text / region / tags prompts, 下载测速, sparkline, scroll-to). Split out of node_list.dart in 1.9.0 (same library, behaviour unchanged).
// Part of 穿云 (GPLv3).

part of 'node_list.dart';

/// A one-line text prompt; null when cancelled, '' allowed (clears the value).
/// 1.4.1: the dialog owns (and disposes) its text controller; [obscure] hides a password.
Future<String?> museAskText(
  BuildContext context,
  String title, {
  String initial = '',
  String? hint,
  int maxLines = 1,
  bool obscure = false,
}) => showDialog<String>(
  context: context,
  builder: (c) => _MuseAskTextDialog(title: title, initial: initial, hint: hint, maxLines: obscure ? 1 : maxLines, obscure: obscure),
);

class _MuseAskTextDialog extends StatefulWidget {
  const _MuseAskTextDialog({required this.title, required this.initial, this.hint, required this.maxLines, required this.obscure});

  final String title;
  final String initial;
  final String? hint;
  final int maxLines;
  final bool obscure;

  @override
  State<_MuseAskTextDialog> createState() => _MuseAskTextDialogState();
}

class _MuseAskTextDialogState extends State<_MuseAskTextDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  late bool _hidden = widget.obscure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: MuseSize.dialogText,
      child: TextField(
        key: const ValueKey('ask_text_field'),
        controller: _controller,
        autofocus: true,
        maxLines: widget.maxLines,
        obscureText: _hidden,
        autocorrect: !widget.obscure,
        enableSuggestions: !widget.obscure,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIcon: widget.obscure
              ? IconButton(
                  key: const ValueKey('ask_text_reveal'),
                  tooltip: _hidden ? '显示内容' : '隐藏内容',
                  icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hidden = !_hidden),
                )
              : null,
        ),
        onSubmitted: widget.maxLines == 1 ? (v) => Navigator.of(context).pop(v.trim()) : null,
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      FilledButton(
        key: const ValueKey('ask_text_ok'),
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('确定'),
      ),
    ],
  );
}

/// 1.5.0 #24: 下载测速 (5 MB through the node in use) inside the node detail sheet; closing the
/// sheet stops it.
class MuseDownloadTestRow extends StatefulWidget {
  const MuseDownloadTestRow({super.key, required this.port});

  final int port;

  @override
  State<MuseDownloadTestRow> createState() => _MuseDownloadTestRowState();
}

class _MuseDownloadTestRowState extends State<MuseDownloadTestRow> {
  MuseSpeedTest? _test;
  String? _result;
  bool _failed = false;

  Future<void> _run() async {
    final test = MuseSpeedTest(port: widget.port);
    setState(() {
      _test = test;
      _result = null;
      _failed = false;
    });
    try {
      final bps = await test.run();
      if (!mounted) return;
      setState(() => _result = museSpeedText(bps));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _result = '下载测速失败：$e';
      });
    } finally {
      if (mounted) setState(() => _test = null);
    }
  }

  @override
  void dispose() {
    _test?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final running = _test != null;
    return Row(
      key: const ValueKey('node_download_test'),
      children: [
        Expanded(
          child: Text(
            running ? '正在下载 5 MB…' : (_result ?? '下载测速（约 5 MB 流量）'),
            style: MuseType.body(context).copyWith(
              color: _failed ? MusePalette.red : (_result == null || running ? mt.text2 : null),
              fontFeatures: MuseType.tabular,
            ),
          ),
        ),
        const SizedBox(width: MuseSpace.s8),
        TextButton(
          key: const ValueKey('node_download_test_button'),
          onPressed: running ? () => _test?.cancel() : _run,
          child: Text(running ? '停止' : (_result == null ? '开始' : '再测')),
        ),
      ],
    );
  }
}

/// 1.6.0 #29: the last delays of a node as a small line (gaps where a test got no answer).
class MuseSparkline extends StatelessWidget {
  const MuseSparkline({super.key, required this.points});

  /// heights 0–1 (1 = slowest), null = no answer (logic/node_tools.dart museSparkline)
  final List<double?> points;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('node_sparkline'),
    height: MuseSize.sparkHeight,
    child: CustomPaint(painter: _SparkPainter(points, museBrandOf(context), MusePalette.red), size: Size.infinite),
  );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color, this.missColor);

  final List<double?> points;
  final Color color;
  final Color missColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final line = Paint()
      ..color = color
      ..strokeWidth = MuseSize.sparkStroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..color = color;
    final miss = Paint()..color = missColor;
    final step = size.width / (points.length - 1);
    final pad = MuseSize.sparkDot;
    final h = size.height - pad * 2;
    Offset? prev;
    for (var i = 0; i < points.length; i++) {
      final v = points[i];
      final x = i * step;
      if (v == null) {
        canvas.drawCircle(Offset(x.clamp(pad, size.width - pad), size.height - pad), pad, miss);
        prev = null;
        continue;
      }
      // faster = higher on the line
      final p = Offset(x, pad + h * v);
      if (prev != null) canvas.drawLine(prev, p, line);
      canvas.drawCircle(Offset(x.clamp(pad, size.width - pad), p.dy), pad, dot);
      prev = p;
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.points.join(',') != points.join(',') || old.color != color;
}

/// 1.6.0 #32: pick a node's region by hand; '' = 按名称自动识别, null = cancelled.
Future<String?> museAskRegion(BuildContext context, {String current = ''}) => showDialog<String>(
  context: context,
  builder: (c) => SimpleDialog(
    key: const ValueKey('node_region_dialog'),
    title: const Text('指定地区'),
    children: [
      SimpleDialogOption(
        key: const ValueKey('node_region_auto'),
        onPressed: () => Navigator.of(c).pop(''),
        child: Text('按名称自动识别${current.isEmpty ? '（当前）' : ''}'),
      ),
      for (final e in museCountryNames.entries)
        SimpleDialogOption(
          key: ValueKey('node_region_${e.key}'),
          onPressed: () => Navigator.of(c).pop(e.key),
          child: Text('${museCountryFlag(e.key) ?? ''} ${e.value}${current == e.key ? '（当前）' : ''}'.trim()),
        ),
    ],
  ),
);

/// 1.6.0 #33: choose a node's tags (presets + ones already used + a new one); null = cancelled.
Future<List<String>?> museAskNodeTags(BuildContext context, {required List<String> current, required List<String> known}) =>
    showDialog<List<String>>(
      context: context,
      builder: (c) => _MuseTagDialog(current: current, known: known),
    );

class _MuseTagDialog extends StatefulWidget {
  const _MuseTagDialog({required this.current, required this.known});

  final List<String> current;
  final List<String> known;

  @override
  State<_MuseTagDialog> createState() => _MuseTagDialogState();
}

class _MuseTagDialogState extends State<_MuseTagDialog> {
  late final List<String> _all = [...museCleanNodeTags([...museNodeTagPresets, ...widget.known, ...widget.current], max: 64)];
  late final Set<String> _on = {...widget.current};
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final v = museCleanNodeTags([_text.text]);
    if (v.isEmpty) return;
    setState(() {
      if (!_all.contains(v.first)) _all.add(v.first);
      _on.add(v.first);
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('node_tags_dialog'),
    title: const Text('标签'),
    content: SizedBox(
      width: MuseSize.dialogText,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: MuseSpace.s8,
            runSpacing: MuseSpace.s8,
            children: [
              for (final t in _all)
                FilterChip(
                  key: ValueKey('node_tag_$t'),
                  label: Text(t),
                  selected: _on.contains(t),
                  onSelected: (v) => setState(() => v ? _on.add(t) : _on.remove(t)),
                ),
            ],
          ),
          const SizedBox(height: MuseSpace.s12),
          TextField(
            key: const ValueKey('node_tag_new'),
            controller: _text,
            maxLength: 12,
            decoration: InputDecoration(
              isDense: true,
              hintText: '新标签，如 低倍率',
              suffixIcon: IconButton(key: const ValueKey('node_tag_add'), tooltip: '添加标签', icon: const Icon(Icons.add_outlined), onPressed: _add),
            ),
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
      FilledButton(
        key: const ValueKey('node_tags_save'),
        onPressed: () => Navigator.of(context).pop([for (final t in _all) if (_on.contains(t)) t]),
        child: const Text('保存'),
      ),
    ],
  );
}

/// 1.6.0 C5: scrolls [scroll] until the widget with [key] is built (rows are built lazily), then
/// brings it into view. False when it is never built (folded section, filtered out).
Future<bool> museScrollToKey(ScrollController scroll, GlobalKey key, {int maxSteps = 400}) async {
  if (!scroll.hasClients) return false;
  Future<bool> reveal() async {
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted || !scroll.hasClients) return false;
    await Scrollable.ensureVisible(ctx, alignment: 0.3, duration: MuseMotion.common);
    return true;
  }

  // 1.10.2: every step waits for a frame; the list may be gone by then (the page was left), so the
  // controller is checked again each time instead of throwing 「not attached to any scroll views」
  if (await reveal()) return true;
  if (!scroll.hasClients) return false;
  scroll.jumpTo(scroll.position.minScrollExtent);
  await WidgetsBinding.instance.endOfFrame;
  for (var i = 0; i < maxSteps; i++) {
    if (await reveal()) return true;
    if (!scroll.hasClients) return false;
    final p = scroll.position;
    if (p.pixels >= p.maxScrollExtent) break;
    scroll.jumpTo(math.min(p.pixels + p.viewportDimension * 0.8, p.maxScrollExtent));
    await WidgetsBinding.instance.endOfFrame;
  }
  return reveal();
}
