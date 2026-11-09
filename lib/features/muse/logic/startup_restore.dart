// 穿云 1.19.3: 启动恢复连接（电脑开机 / 重启 / 异常退出后再打开）遇到一次连接或 gRPC 错误时不再
// 立刻放弃。
//
// 1.19.2 之前：恢复连接的那一次 connect 只要失败一次（例如本地 gRPC 连接被瞬间重置），
// started_by_user 就被置为 false，下次启动也不再自动连接。现在：失败是传输类错误（连接 / gRPC）时，
// 先释放内核、短暂等待（单次 400 ms，无轮询、无计时器常驻），重新建立 gRPC 通道并确认内核仍应答，
// 再试一次；仍失败（或内核不应答、或错误本身不是传输类，例如配置无效）才判失败、按原逻辑处理。
// 每条失败路径都先释放内核。用户主动断开 / 取消（[stillWanted] 为 false）时不重试。
import 'package:fpdart/fpdart.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';

/// 两次尝试之间的等待（单次、短退避）。
const museRestoreRetryDelay = Duration(milliseconds: 400);

/// 启动恢复连接最多尝试的次数（首次 + 重试 1 次）。
const museRestoreMaxAttempts = 2;

const _transientText = [
  'http/2',
  'forcefully terminated',
  'no longer active',
  'connection is being',
  'stream error',
  'connection closed',
  'connection reset',
  'connection refused',
  'connection terminated',
  'socketexception',
  'broken pipe',
  'failed to start background core',
  'background core is not started yet',
];

const _transientCodes = {
  StatusCode.unavailable,
  StatusCode.unknown,
  StatusCode.cancelled,
  StatusCode.internal,
  StatusCode.aborted,
  StatusCode.deadlineExceeded,
};

/// 是否是连接 / gRPC 传输类的一次性错误（值得重建通道再试）。配置无效、权限不足、内核明确
/// 拒绝启动等都不是。
bool museIsTransientCoreFailure(ConnectionFailure failure) {
  if (failure is! UnexpectedConnectionFailure) return false;
  final e = failure.error;
  if (e == null) return false;
  if (e is GrpcError) return _transientCodes.contains(e.code);
  final text = '$e'.toLowerCase();
  return _transientText.any(text.contains);
}

/// 启动恢复连接：[attempt] 失败且 [isTransient] 时，释放内核 → 等待 [delay] → [reopenChannel]
/// （重建 gRPC 通道，内核应答时为 true）→ 再 [attempt] 一次。返回最后一次的结果。
///
/// 只要最终是失败，就已经调用过 [release]；[stillWanted] 为 false（用户已断开 / 取消）时
/// 直接返回首次结果，交给用户自己的断开路径处理（不重试、不重复释放）。
Future<Either<F, Unit>> museRestoreConnect<F>({
  required Future<Either<F, Unit>> Function() attempt,
  required bool Function(F failure) isTransient,
  required Future<bool> Function() reopenChannel,
  required Future<void> Function() release,
  required bool Function() stillWanted,
  Future<void> Function(Duration) wait = _wait,
  Duration delay = museRestoreRetryDelay,
  void Function(String line)? log,
}) async {
  final first = await attempt();
  final failure = first.getLeft().toNullable();
  if (failure == null) return first;
  if (!stillWanted()) return first;
  await release();
  if (!isTransient(failure)) {
    log?.call('启动恢复连接失败（非连接类错误，不重试）：$failure');
    return first;
  }
  log?.call('启动恢复连接遇到连接错误，${delay.inMilliseconds} ms 后重建通道再试一次：$failure');
  await wait(delay);
  if (!stillWanted()) return first;
  if (!await reopenChannel()) {
    log?.call('重建通道后内核仍无应答，判定恢复失败');
    return first;
  }
  if (!stillWanted()) return first;
  final second = await attempt();
  if (second.isLeft()) {
    if (stillWanted()) await release();
    log?.call('重试仍失败，判定恢复失败：${second.getLeft().toNullable()}');
  } else {
    log?.call('重试成功，已恢复连接');
  }
  return second;
}

Future<void> _wait(Duration d) => Future<void>.delayed(d);
