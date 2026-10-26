// 穿云 1.6.0 (batch 2, nodes B logic): #31 去重模式, #34 收藏排序, #35 JSON 配置复制, #40 清除预览.
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/muse/logic/node_share.dart';
import 'package:hiddify/features/muse/logic/node_tools.dart';

void main() {
  final nodes = [
    ('a', 'h', 1, 'x'),
    ('b', 'H', 1, 'y'),
    ('c', 'h', 1, 'x'),
    ('d', '', 1, 'x'),
  ];
  Set<String> dedup(MuseDedupMode m) => museDuplicateTagsBy(nodes, mode: m, tag: (n) => n.$1, host: (n) => n.$2, port: (n) => n.$3, params: (n) => n.$4);

  test('#31 dedup modes', () {
    expect(dedup(MuseDedupMode.addressPort), {'b', 'c'});
    expect(dedup(MuseDedupMode.fullParams), {'c'});
  });

  test('#34 reorder + order sync', () {
    expect(museReorderFavorites(['a', 'b', 'c'], 0, 3), ['b', 'c', 'a']);
    expect(museReorderFavorites(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
    expect(museReorderFavorites(['a'], 5, 0), ['a']);
    expect(museFavoriteOrder(['c', 'a', 'z'], {'a', 'b', 'c'}), ['c', 'a', 'b']);
  });

  test('#40 clear plan keeps selected and favorites', () {
    final p = museClearPlan(['a', 'b', 'c', 'd'], unavailable: {'a', 'b', 'c'}, selected: 'a', favorites: {'b'});
    expect(p.remove, ['c']);
    expect(p.keep, ['a', 'b', 'd']);
    expect(museClearPlan(['a'], unavailable: {}, selected: '').isEmpty, true);
  });

  test('#35 JSON 配置 copy', () {
    const raw = '{"outbounds":[{"tag":"t","type":"vless","server":"s"}]}';
    expect(museNodeAsJsonConfig(raw, 't'), contains('"server": "s"'));
    expect(museNodeAsJsonConfig(raw, 'x'), isNull);
    expect(museNodeAsJsonConfig('bad', 't'), isNull);
  });
}
