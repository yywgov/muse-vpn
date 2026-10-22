import 'package:dart_mappable/dart_mappable.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';
import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';

part 'log_level.mapper.dart';

@MappableEnum()
enum LogLevel {
  trace,
  debug,
  info,
  warn,
  error,
  fatal,
  panic;

  /// [LogLevel] selectable by user as preference. Stops at error: fatal and
  /// panic are what the core says on its way down, so choosing them as a floor
  /// would mean asking to be told nothing until it is already too late.
  static List<LogLevel> get choices => values.takeFirst(5);

  /// The core switches itself into debug mode at these levels — see
  /// `static.debug = static.debug || static.logLevel <= LogLevel_DEBUG` in
  /// hiddify-core's buildconfighelper.go. Reading the same rule here keeps the
  /// app's own debug decisions in step with the core's, from one setting.
  bool get isVerbose => index <= LogLevel.debug.index;

  Color? get color => switch (this) {
    trace => MusePalette.brandLight,
    debug => MusePalette.lightText3,
    info => MusePalette.green,
    warn => MusePalette.orange,
    error => MusePalette.red,
    fatal => MusePalette.red,
    panic => MusePalette.red,
  };
}
