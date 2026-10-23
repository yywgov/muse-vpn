import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';

enum ProfilesSort {
  lastUpdate,
  name;

  String present(Translations t) {
    return switch (this) {
      lastUpdate => t.dialogs.sortProfiles.sort.lastUpdate,
      name => t.dialogs.sortProfiles.sort.name,
    };
  }

  /// Human-readable label for the current sort direction, worded per type.
  String directionLabel(Translations t, SortMode mode) {
    return switch (this) {
      lastUpdate =>
        mode == SortMode.descending
            ? t.dialogs.sortProfiles.direction.newestFirst
            : t.dialogs.sortProfiles.direction.oldestFirst,
      name => mode == SortMode.ascending ? "A → Z" : "Z → A",
    };
  }

  IconData get icon => switch (this) {
    lastUpdate => Icons.history_outlined,
    name => Icons.sort_by_alpha_outlined,
  };
}

enum SortMode { ascending, descending }
