// 穿云 1.14.0 R15 - 订阅更新出错不覆盖: an update that brings back nothing usable keeps the last
// good nodes. The download already fails on a network error and the core's check fails on a body
// it can't read; this adds what neither catches — an empty answer, a web page instead of nodes, a
// list with no nodes, and a list that suddenly lost most of its nodes — and the repository puts the
// last good file back if saving fails half-way. Pure and never throws.
// Part of 穿云 (GPLv3).

import 'package:hiddify/features/muse/logic/sub_tools.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';

/// Every message ends with this, so the user knows nothing was lost.
const museSubKeptNote = '已保留上次成功更新的节点';

/// A drop this steep (and from at least [museSubDropMinBefore] nodes) is held back.
const museSubDropRatio = 0.3;
const museSubDropMinBefore = 10;

const _dropLead = '节点数从 ';

/// Why [newBody] (just downloaded) should not replace [oldConfig] (the saved profile), or null
/// when it may go on to the core's own check. [force]: the user confirmed a steep drop.
String? museSubUpdateProblem(String oldConfig, String newBody, {bool force = false}) {
  final body = newBody.trim();
  if (body.isEmpty) return '订阅返回了空内容，$museSubKeptNote';
  final head = body.length > 512 ? body.substring(0, 512).toLowerCase() : body.toLowerCase();
  if (head.startsWith('<!doctype html') || head.startsWith('<html') || (head.startsWith('<') && head.contains('<body'))) {
    return '订阅返回的是网页而不是节点（链接可能已失效或需要登录），$museSubKeptNote';
  }
  final after = museSubPreview(body);
  // a form the preview can't count is left to the core's check
  if (after.format == MuseSubFormat.unknown && after.formatLabel == null) return null;
  if (after.nodes == 0) return '订阅里没有任何节点，$museSubKeptNote';
  if (force || oldConfig.trim().isEmpty) return null;
  final before = museSubPreview(oldConfig).nodes;
  if (before >= museSubDropMinBefore && after.nodes < before * museSubDropRatio) {
    return museSubDropMessage(before, after.nodes);
  }
  return null;
}

String museSubDropMessage(int before, int after) => '$_dropLead$before 个骤减到 $after 个，可能是订阅出错，$museSubKeptNote';

/// Whether [message] is the steep-drop one (the user may still choose to update).
bool museSubIsDropMessage(String? message) => message != null && message.startsWith(_dropLead) && message.endsWith(museSubKeptNote);

/// One Chinese line for why an update failed, ending with [museSubKeptNote] (background updates
/// show it in the toast and the notification). Null for a cancelled update.
String? museSubFailureReason(Object? error) {
  bool chinese(String s) => RegExp(r'[\u4e00-\u9fff]').hasMatch(s);
  String kept(String s) => s.contains(museSubKeptNote) ? s : '${s.replaceAll(RegExp(r'[，。\s]+$'), '')}，$museSubKeptNote';
  return switch (error) {
    ProfileCancelByUserFailure() => null,
    ProfileInvalidConfigFailure(:final message) when message != null && chinese(message) => kept(message),
    ProfileInvalidConfigFailure() => '订阅内容无法解析，$museSubKeptNote',
    ProfileUnexpectedFailure(:final error) when error is String && chinese(error) => kept(error),
    ProfileInvalidUrlFailure() => '订阅链接无效，$museSubKeptNote',
    _ => '更新出错，$museSubKeptNote',
  };
}

/// The system notification for background updates that failed.
String museSubBulkFailText(List<String> names, String? reason) => '${names.join('、')}：${reason ?? '已保留原有节点'}';
