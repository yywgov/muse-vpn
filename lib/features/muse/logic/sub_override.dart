// 穿云 1.9.0 #15 - 订阅覆写: per-subscription rules, extra nodes and proxy groups.
//
// The saved subscription is never changed. At connect time the app composes what the core reads:
// - rules go into the app's own rule list (the one both cores already read), right after 局域网;
// - extra nodes and groups go into a runtime copy next to the profile (`<profile>.override`),
//   which the core is started on instead of the profile. Without an override (or with an empty
//   one) the core gets the profile path and the options exactly as before.
// An update of the subscription only rewrites the profile, so the override (kept in settings by
// profile id) applies to the new body at the next connect.
// 兼容内核 reads the same composition: a sing-box JSON body through the existing JSON mapping,
// a YAML body gets its groups as YAML (include-all + filter) and its extra nodes as a local file
// provider, a link list gets the links appended.
// Part of 穿云 (GPLv3).

import 'dart:convert';
import 'dart:io';

import 'package:hiddify/features/muse/logic/node_form.dart';
import 'package:hiddify/features/muse/logic/rules_tools.dart' show museLanRuleName;
import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

/// Kinds of match a 覆写 rule can use (the same fields 分流 rules use).
enum MuseOverrideMatch {
  domain('domain', '域名'),
  domainSuffix('domain_suffix', '域名后缀'),
  domainKeyword('domain_keyword', '域名关键词'),
  ipCidr('ip_cidr', 'IP 段');

  const MuseOverrideMatch(this.key, this.label);
  final String key;
  final String label;

  static MuseOverrideMatch fromKey(Object? k) => values.firstWhere((e) => e.key == k, orElse: () => domainSuffix);
}

/// Where a matched connection goes.
enum MuseOverrideTarget {
  proxy('proxy', '代理'),
  direct('direct', '直连'),
  block('block', '拦截');

  const MuseOverrideTarget(this.key, this.label);
  final String key;
  final String label;

  static MuseOverrideTarget fromKey(Object? k) => values.firstWhere((e) => e.key == k, orElse: () => proxy);
}

class MuseOverrideRule {
  const MuseOverrideRule({required this.match, required this.value, this.target = MuseOverrideTarget.proxy});

  final MuseOverrideMatch match;
  final String value;
  final MuseOverrideTarget target;

  Map<String, Object?> toJson() => {'match': match.key, 'value': value, 'target': target.key};

  static MuseOverrideRule? fromJson(Object? j) {
    if (j is! Map) return null;
    final v = (j['value'] ?? '').toString().trim();
    if (v.isEmpty) return null;
    return MuseOverrideRule(match: MuseOverrideMatch.fromKey(j['match']), value: v, target: MuseOverrideTarget.fromKey(j['target']));
  }
}

/// A proxy group added to the subscription: its members are the subscription's (and the extra)
/// nodes whose name matches [filter] (a regular expression; empty = every node).
class MuseOverrideGroup {
  const MuseOverrideGroup({required this.name, this.urlTest = false, this.filter = ''});

  final String name;

  /// 自动选择 (lowest latency) instead of 手动选择
  final bool urlTest;
  final String filter;

  Map<String, Object?> toJson() => {'name': name, 'type': urlTest ? 'urltest' : 'select', 'filter': filter};

  static MuseOverrideGroup? fromJson(Object? j) {
    if (j is! Map) return null;
    final n = (j['name'] ?? '').toString().trim();
    if (n.isEmpty) return null;
    return MuseOverrideGroup(name: n, urlTest: j['type'] == 'urltest', filter: (j['filter'] ?? '').toString());
  }

  bool matches(String node) {
    if (filter.trim().isEmpty) return true;
    try {
      return RegExp(filter).hasMatch(node);
    } catch (_) {
      return node.contains(filter);
    }
  }
}

class MuseSubOverride {
  const MuseSubOverride({this.enabled = true, this.rules = const [], this.nodes = const [], this.groups = const [], this.edits = const {}});

  final bool enabled;
  final List<MuseOverrideRule> rules;

  /// share links, one per entry
  final List<String> nodes;
  final List<MuseOverrideGroup> groups;

  /// 1.14.0 R21: local patches of subscription nodes, by node name (编辑节点)
  final Map<String, MuseNodeEdit> edits;

  /// Nothing to apply: the core gets the subscription exactly as before.
  bool get isEmpty => !enabled || (rules.isEmpty && nodes.isEmpty && groups.isEmpty && edits.isEmpty);

  /// Whether the body needs a runtime copy (rules alone go into the options).
  bool get changesBody => !isEmpty && (nodes.isNotEmpty || groups.isNotEmpty || edits.isNotEmpty);

  MuseSubOverride copyWith({bool? enabled, List<MuseOverrideRule>? rules, List<String>? nodes, List<MuseOverrideGroup>? groups, Map<String, MuseNodeEdit>? edits}) =>
      MuseSubOverride(
        enabled: enabled ?? this.enabled,
        rules: rules ?? this.rules,
        nodes: nodes ?? this.nodes,
        groups: groups ?? this.groups,
        edits: edits ?? this.edits,
      );

  /// [tag]'s patch replaced ([e] empty = removed).
  MuseSubOverride withEdit(String tag, MuseNodeEdit e) => copyWith(edits: {...edits}..remove(tag)..addAll({if (!e.isEmpty) tag: e}));

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'rules': [for (final r in rules) r.toJson()],
    'nodes': nodes,
    'groups': [for (final g in groups) g.toJson()],
    if (edits.isNotEmpty) 'edits': {for (final e in edits.entries) e.key: e.value.toJson()},
  };

  static MuseSubOverride fromJson(Object? j) {
    if (j is! Map) return const MuseSubOverride();
    return MuseSubOverride(
      enabled: j['enabled'] != false,
      rules: [for (final r in (j['rules'] is List ? j['rules'] as List : const [])) ?MuseOverrideRule.fromJson(r)],
      nodes: museOverrideLinks(j['nodes'] is List ? (j['nodes'] as List).join('\n') : (j['nodes'] ?? '').toString()),
      groups: [for (final g in (j['groups'] is List ? j['groups'] as List : const [])) ?MuseOverrideGroup.fromJson(g)],
      edits: {
        if (j['edits'] is Map)
          for (final e in (j['edits'] as Map).entries)
            if (!MuseNodeEdit.fromJson(e.value).isEmpty) '${e.key}': MuseNodeEdit.fromJson(e.value),
      },
    );
  }
}

/// Share links in [text] (one per line; anything without "://" is ignored).
List<String> museOverrideLinks(String text) => [
  for (final l in const LineSplitter().convert(text))
    if (l.trim().contains('://')) l.trim(),
];

/// All overrides, by profile id (setting `muse_sub_overrides`). A broken value reads as none.
Map<String, MuseSubOverride> museParseOverrides(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return {};
    return {for (final e in j.entries) e.key.toString(): MuseSubOverride.fromJson(e.value)};
  } catch (_) {
    return {};
  }
}

/// Encodes [all], leaving out empty entries of profiles that have none.
String museEncodeOverrides(Map<String, MuseSubOverride> all) => jsonEncode({
  for (final e in all.entries)
    if (e.value.enabled == false || e.value.rules.isNotEmpty || e.value.nodes.isNotEmpty || e.value.groups.isNotEmpty || e.value.edits.isNotEmpty)
      e.key: e.value.toJson(),
});

/// The app's rule list (proto3 JSON) with [o]'s rules right after 局域网. Returns [routeRule]
/// itself when there is nothing to add, so options without an override stay identical.
Map<String, dynamic> museApplyOverrideRules(Map<String, dynamic> routeRule, MuseSubOverride? o) {
  if (o == null || o.isEmpty || o.rules.isEmpty) return routeRule;
  final rr = RouteRule.create()..mergeFromProto3Json(routeRule, ignoreUnknownFields: true);
  final list = [...rr.rules];
  final at = list.isNotEmpty && list.first.name == museLanRuleName ? 1 : 0;
  final added = <Rule>[];
  for (var i = 0; i < o.rules.length; i++) {
    final r = o.rules[i];
    final rule = Rule(
      enabled: true,
      name: 'override:${i + 1}',
      outbound: switch (r.target) {
        MuseOverrideTarget.proxy => Outbound.proxy,
        MuseOverrideTarget.direct => Outbound.direct,
        MuseOverrideTarget.block => Outbound.block,
      },
    );
    switch (r.match) {
      case MuseOverrideMatch.domain:
        rule.domains.add(r.value);
      case MuseOverrideMatch.domainSuffix:
        rule.domainSuffixes.add(r.value);
      case MuseOverrideMatch.domainKeyword:
        rule.domainKeywords.add(r.value);
      case MuseOverrideMatch.ipCidr:
        rule.ipCidrs.add(r.value);
    }
    added.add(rule);
  }
  list.insertAll(at, added);
  for (var k = 0; k < list.length; k++) {
    if (list[k].listOrder != k) list[k] = list[k].deepCopy()..listOrder = k;
  }
  final out = RouteRule(rules: list);
  return out.toProto3Json()! as Map<String, dynamic>;
}

/// Path of the runtime copy the core runs when [o] changes the body.
String museOverrideRunPath(String profilePath) => '$profilePath.override';

/// Path of the extra nodes a YAML subscription reads as a local provider (兼容内核).
String museOverrideNodesPath(String profilePath) => '$profilePath.override-nodes';

const museOverrideProvider = 'muse-override-nodes';

const _groupTypes = {'selector', 'urltest', 'direct', 'block', 'dns', 'balancer'};

/// The body the core runs: [body] with [o]'s extra nodes and groups, or null when nothing changes
/// (no override, or a form this override cannot add to). [extraOutbounds] are the extra nodes
/// already converted to the JSON form (only needed for a JSON body). [nodesPath] is where the
/// extra links are written for a YAML body.
String? museOverrideBody(String body, MuseSubOverride? o, {List<Map<String, dynamic>> extraOutbounds = const [], String? nodesPath}) {
  if (o == null || !o.changesBody) return null;
  switch (museDetectSubFormat(body)) {
    case MuseSubFormat.singBox:
      return _jsonBody(body, o, extraOutbounds);
    case MuseSubFormat.clash:
      return _yamlBody(body, o, nodesPath);
    case MuseSubFormat.links || MuseSubFormat.base64:
      if (o.nodes.isEmpty) return null;
      return '${museSubPlainText(body).trimRight()}\n${o.nodes.join('\n')}\n';
    default:
      return null;
  }
}

String? _jsonBody(String body, MuseSubOverride o, List<Map<String, dynamic>> extra) {
  final Object? root;
  try {
    root = jsonDecode(body);
  } catch (_) {
    return null;
  }
  final isMap = root is Map<String, dynamic>;
  final outbounds = <dynamic>[...(isMap ? (root['outbounds'] as List? ?? const []) : root! as List)];
  final tags = <String>{for (final ob in outbounds) if (ob is Map && ob['tag'] is String) ob['tag'] as String};
  for (final ob in extra) {
    final copy = Map<String, dynamic>.of(ob);
    var tag = (copy['tag'] ?? copy['type'] ?? 'node').toString();
    if (tags.contains(tag)) {
      var n = 2;
      while (tags.contains('$tag $n')) {
        n++;
      }
      tag = '$tag $n';
    }
    copy['tag'] = tag;
    tags.add(tag);
    outbounds.add(copy);
  }
  // 1.14.0 R21: local patches over the nodes they name (a node gone from the subscription has none)
  if (o.edits.isNotEmpty) {
    for (var i = 0; i < outbounds.length; i++) {
      final ob = outbounds[i];
      if (ob is! Map || _groupTypes.contains(ob['type'])) continue;
      final e = o.edits[ob['tag']];
      if (e != null) outbounds[i] = e.applyTo(Map<String, dynamic>.from(ob));
    }
  }
  final nodes = [
    for (final ob in outbounds)
      if (ob is Map && ob['tag'] is String && !_groupTypes.contains(ob['type'])) ob['tag'] as String,
  ];
  for (final g in o.groups) {
    if (tags.contains(g.name)) continue; // never replace one of the subscription's own
    final members = [for (final n in nodes) if (g.matches(n)) n];
    if (members.isEmpty) continue; // an empty group would stop the core from starting
    outbounds.add({'type': g.urlTest ? 'urltest' : 'selector', 'tag': g.name, 'outbounds': members});
    tags.add(g.name);
  }
  if (isMap) {
    final copy = Map<String, dynamic>.of(root)..['outbounds'] = outbounds;
    return const JsonEncoder.withIndent('  ').convert(copy);
  }
  return const JsonEncoder.withIndent('  ').convert(outbounds);
}

String _yamlQuote(String s) => jsonEncode(s); // a JSON string is a valid YAML flow scalar

String? _yamlBody(String body, MuseSubOverride o, String? nodesPath) {
  final lines = const LineSplitter().convert(body);
  final out = <String>[...lines];
  final groupLines = [
    for (final g in o.groups)
      '  - {name: ${_yamlQuote(g.name)}, type: ${g.urlTest ? 'url-test' : 'select'}, include-all: true${g.filter.trim().isEmpty ? '' : ', filter: ${_yamlQuote(g.filter)}'}}',
  ];
  final providerLines = o.nodes.isEmpty || nodesPath == null
      ? const <String>[]
      : ['  $museOverrideProvider: {type: file, path: ${_yamlQuote(nodesPath)}}'];
  if (groupLines.isEmpty && providerLines.isEmpty) return null;
  void inject(String key, List<String> add) {
    if (add.isEmpty) return;
    final i = out.indexWhere((l) => RegExp('^$key\\s*:\\s*(#.*)?\$').hasMatch(l));
    if (i >= 0) {
      // match the indent the subscription's own entries use (a list may sit at column 0)
      final next = out.skip(i + 1).firstWhere((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'), orElse: () => '');
      final indent = next.length - next.trimLeft().length;
      final list = add.first.trimLeft().startsWith('-');
      final pad = (indent == 0 && !list) || next.isEmpty || RegExp(r'^\S').hasMatch(next) && !next.startsWith('-') ? '  ' : ' ' * indent;
      out.insertAll(i + 1, [for (final a in add) '$pad${a.trimLeft()}']);
    } else if (out.any((l) => RegExp('^$key\\s*:\\s*\\[\\s*\\]').hasMatch(l))) {
      final j = out.indexWhere((l) => RegExp('^$key\\s*:\\s*\\[\\s*\\]').hasMatch(l));
      out[j] = '$key:';
      out.insertAll(j + 1, add);
    } else {
      out
        ..add('$key:')
        ..addAll(add);
    }
  }

  inject('proxy-providers', providerLines);
  inject('proxy-groups', groupLines);
  return '${out.join('\n')}\n';
}

/// The file the core runs for [profilePath] with [o]: the profile path itself when [o] does not
/// change the body (a stale runtime copy is removed), otherwise the runtime copy written next to
/// it. The profile is only read. [convertLinks] turns the extra links into JSON outbounds (the
/// core's subscription conversion); only asked for a JSON body.
Future<String> museComposeRunFile(
  String profilePath,
  MuseSubOverride? o, {
  Future<List<Map<String, dynamic>>> Function(List<String> links)? convertLinks,
}) async {
  final run = File(museOverrideRunPath(profilePath));
  final nodes = File(museOverrideNodesPath(profilePath));
  if (o == null || !o.changesBody) {
    if (await run.exists()) await run.delete();
    if (await nodes.exists()) await nodes.delete();
    return profilePath;
  }
  final body = await File(profilePath).readAsString();
  var extra = const <Map<String, dynamic>>[];
  if (o.nodes.isNotEmpty && convertLinks != null && museDetectSubFormat(body) == MuseSubFormat.singBox) {
    extra = await convertLinks(o.nodes);
  }
  if (o.nodes.isNotEmpty) await nodes.writeAsString('${o.nodes.join('\n')}\n', flush: true);
  final composed = museOverrideBody(body, o, extraOutbounds: extra, nodesPath: nodes.path);
  if (composed == null) {
    if (await run.exists()) await run.delete();
    return profilePath;
  }
  await run.writeAsString(composed, flush: true);
  return run.path;
}
