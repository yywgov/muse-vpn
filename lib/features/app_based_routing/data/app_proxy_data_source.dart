import 'package:drift/drift.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_backup.dart';
import 'package:hiddify/features/app_based_routing/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/app_based_routing/model/pkg_flag.dart';
import 'package:hiddify/utils/custom_loggers.dart';

part 'app_proxy_data_source.g.dart';

abstract interface class AppProxyDataSource {
  Future<void> updatePkg({required String pkg, required AppProxyMode mode});
  Stream<List<AppProxyEntry>> watchAll({required AppProxyMode mode});
  Stream<List<AppProxyEntry>> watchFilterForDisplay({required Set<String> phonePkgs, required AppProxyMode mode});
  Stream<List<String>> watchActivePackages({required Set<String> phonePkgs, required AppProxyMode mode});
  Future<List<String>> getPkgsByFlag({required PkgFlag flag, required AppProxyMode mode});
  Future<void> importPkgs({required PerAppProxyBackup backup});
  Future<void> applyAutoSelection({required Set<String> autoList, required AppProxyMode mode});
  Future<void> clearAutoSelected({required AppProxyMode mode});
  Future<void> revertForceDeselection({required AppProxyMode mode});
  Future<int> clearAll({required AppProxyMode mode});

  /// 穿云 1.6.0 C9: chooses ([selected]) or un-chooses each of [pkgs] (全选 / 反选 / 剪贴板导入).
  Future<void> setSelected({required Iterable<String> pkgs, required bool selected, required AppProxyMode mode});
}

@DriftAccessor(tables: [AppProxyEntries])
class AppProxyDao extends DatabaseAccessor<Db> with _$AppProxyDaoMixin, InfraLogger implements AppProxyDataSource {
  AppProxyDao(super.db);

  @override
  Future<void> updatePkg({required String pkg, required AppProxyMode mode}) {
    return transaction(() async {
      final entry = await (select(
        appProxyEntries,
      )..where((tbl) => tbl.mode.equalsValue(mode) & tbl.pkgName.equals(pkg))).getSingleOrNull();

      if (entry == null) {
        await into(
          appProxyEntries,
        ).insert(AppProxyEntriesCompanion.insert(mode: mode, pkgName: pkg, flags: Value(PkgFlag.userSelection.add(0))));
        return;
      }

      final flag = entry.flags;
      final isAutoSelection = PkgFlag.autoSelection.check(flag);

      if (!isAutoSelection && PkgFlag.userSelection.check(flag)) {
        await (delete(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode) & tbl.pkgName.equals(pkg))).go();
        return;
      }

      // auto: dash -> removed -> yours -> dash. A removed app left over from auto selection becomes yours.
      int newFlag;
      if (!isAutoSelection || PkgFlag.forceDeselection.check(flag)) {
        newFlag = PkgFlag.userSelection.add(flag);
      } else if (PkgFlag.userSelection.check(flag)) {
        newFlag = PkgFlag.userSelection.remove(flag);
      } else {
        newFlag = PkgFlag.forceDeselection.add(flag);
      }

      await (update(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode) & tbl.pkgName.equals(pkg))).write(
        AppProxyEntriesCompanion(flags: Value(newFlag)),
      );
    });
  }

  // 穿云 1.6.0 C9: chosen = your pick (a removed automatic pick comes back as yours); un-chosen =
  // your pick deleted, an automatic pick marked removed (so the next automatic update keeps it out)
  @override
  Future<void> setSelected({required Iterable<String> pkgs, required bool selected, required AppProxyMode mode}) {
    final list = pkgs.toSet();
    if (list.isEmpty) return Future.value();
    return transaction(() async {
      final rows = await (select(
        appProxyEntries,
      )..where((tbl) => tbl.mode.equalsValue(mode) & tbl.pkgName.isIn(list))).get();
      final existing = {for (final r in rows) r.pkgName: r.flags};
      for (final pkg in list) {
        final flag = existing[pkg];
        if (selected) {
          if (flag == null) {
            await into(appProxyEntries).insert(
              AppProxyEntriesCompanion.insert(mode: mode, pkgName: pkg, flags: Value(PkgFlag.userSelection.add(0))),
            );
          } else if (!PkgFlag.userSelection.check(flag) || PkgFlag.forceDeselection.check(flag)) {
            await (update(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode) & tbl.pkgName.equals(pkg))).write(
              AppProxyEntriesCompanion(flags: Value(PkgFlag.userSelection.add(flag))),
            );
          }
        } else if (flag != null) {
          if (PkgFlag.autoSelection.check(flag)) {
            await (update(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode) & tbl.pkgName.equals(pkg))).write(
              AppProxyEntriesCompanion(flags: Value(PkgFlag.forceDeselection.add(flag))),
            );
          } else {
            await (delete(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode) & tbl.pkgName.equals(pkg))).go();
          }
        }
      }
    });
  }

  @override
  Stream<List<AppProxyEntry>> watchAll({required AppProxyMode mode}) {
    final query = select(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode));
    return query.watch();
  }

  @override
  Stream<List<AppProxyEntry>> watchFilterForDisplay({required Set<String> phonePkgs, required AppProxyMode mode}) {
    if (phonePkgs.isEmpty) return Stream.value([]);

    return (select(appProxyEntries)..where((tbl) {
          final modeFilter = tbl.mode.equalsValue(mode);
          final packageFilter = tbl.pkgName.isIn(phonePkgs);
          return modeFilter & packageFilter;
        }))
        .watch();
  }

  @override
  Stream<List<String>> watchActivePackages({required Set<String> phonePkgs, required AppProxyMode mode}) {
    if (phonePkgs.isEmpty) return Stream.value([]);

    final query = selectOnly(appProxyEntries)..addColumns([appProxyEntries.pkgName]);

    final modeFilter = appProxyEntries.mode.equalsValue(mode);
    final packageFilter = appProxyEntries.pkgName.isIn(phonePkgs);
    final isForceDeselectionSet = appProxyEntries.flags
        .bitwiseAnd(Constant(PkgFlag.forceDeselection.value))
        .equals(PkgFlag.forceDeselection.value);

    final combinedFilter = modeFilter & packageFilter & isForceDeselectionSet.not();

    query.where(combinedFilter);

    return query.watch().map((rows) {
      return rows.map((row) => row.read(appProxyEntries.pkgName)!).toList();
    });
  }

  @override
  Future<List<String>> getPkgsByFlag({required PkgFlag flag, required AppProxyMode mode}) {
    final query = selectOnly(appProxyEntries)..addColumns([appProxyEntries.pkgName]);
    final filter =
        appProxyEntries.mode.equalsValue(mode) &
        (appProxyEntries.flags.bitwiseAnd(Constant(flag.value)).equals(flag.value));

    query.where(filter);

    return query.map((row) => row.read(appProxyEntries.pkgName)!).get();
  }

  @override
  Future<void> importPkgs({required PerAppProxyBackup backup}) {
    return transaction(() async {
      await (delete(appProxyEntries)..where((tbl) => tbl.flags.equals(0))).go();

      await db.batch((b) {
        b
          ..update(
            appProxyEntries,
            AppProxyEntriesCompanion.custom(
              flags: appProxyEntries.flags.bitwiseAnd(
                Constant(~(PkgFlag.userSelection.value | PkgFlag.forceDeselection.value)),
              ),
            ),
          )
          ..deleteWhere(appProxyEntries, (tbl) => tbl.flags.equals(0))
          ..insertAll(
            db.appProxyEntries,
            <AppProxyEntriesCompanion>[
              ...backup.include.selected.map(
                (pkg) => AppProxyEntriesCompanion.insert(
                  mode: AppProxyMode.include,
                  pkgName: pkg,
                  flags: Value(PkgFlag.userSelection.add(0)),
                ),
              ),
              ...backup.include.deselected.map(
                (pkg) => AppProxyEntriesCompanion.insert(
                  mode: AppProxyMode.include,
                  pkgName: pkg,
                  flags: Value(PkgFlag.forceDeselection.add(0)),
                ),
              ),
              ...backup.exclude.selected.map(
                (pkg) => AppProxyEntriesCompanion.insert(
                  mode: AppProxyMode.exclude,
                  pkgName: pkg,
                  flags: Value(PkgFlag.userSelection.add(0)),
                ),
              ),
              ...backup.exclude.deselected.map(
                (pkg) => AppProxyEntriesCompanion.insert(
                  mode: AppProxyMode.exclude,
                  pkgName: pkg,
                  flags: Value(PkgFlag.forceDeselection.add(0)),
                ),
              ),
            ],
            onConflict: DoUpdate.withExcluded((AppProxyEntries old, AppProxyEntries e) {
              return AppProxyEntriesCompanion.custom(flags: old.flags.bitwiseOr(e.flags));
            }),
          );
      });
    });
  }

  @override
  Future<void> applyAutoSelection({required Set<String> autoList, required AppProxyMode mode}) {
    return transaction(() async {
      // removing all items that have only auto selection
      await (delete(
        appProxyEntries,
      )..where((tbl) => tbl.mode.equalsValue(mode) & tbl.flags.equals(PkgFlag.autoSelection.value))).go();
      // removing auto selection flag from items
      final entriesToUpdate = await (db.select(db.appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode))).get();
      if (entriesToUpdate.isNotEmpty) {
        final updatedCompanions = entriesToUpdate.map((entry) {
          return entry.copyWith(flags: PkgFlag.autoSelection.remove(entry.flags)).toCompanion(false);
        }).toList();
        await db.batch((b) {
          b.replaceAll(db.appProxyEntries, updatedCompanions);
        });
      }
      // adding auto selected
      if (autoList.isNotEmpty) {
        await db.batch((b) {
          b.insertAll(
            db.appProxyEntries,
            autoList.map(
              (pkg) =>
                  AppProxyEntriesCompanion.insert(mode: mode, pkgName: pkg, flags: Value(PkgFlag.autoSelection.add(0))),
            ),
            onConflict: DoUpdate((AppProxyEntries old) {
              return AppProxyEntriesCompanion.custom(flags: old.flags.bitwiseOr(Constant(PkgFlag.autoSelection.value)));
            }),
          );
        });
      }
    });
  }

  @override
  Future<void> clearAutoSelected({required AppProxyMode mode}) {
    return transaction(() async {
      // removing all items that have only auto selection
      await (delete(
        appProxyEntries,
      )..where((tbl) => tbl.mode.equalsValue(mode) & (appProxyEntries.flags.equals(PkgFlag.autoSelection.value)))).go();
      // removing auto selection flag from items
      await (update(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode))).write(
        AppProxyEntriesCompanion.custom(
          flags: appProxyEntries.flags.bitwiseAnd(Constant(~PkgFlag.autoSelection.value)),
        ),
      );
    });
  }

  @override
  Future<void> revertForceDeselection({required AppProxyMode mode}) {
    return transaction(() async {
      // remove forceDeselection flag from flags
      await (update(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode))).write(
        AppProxyEntriesCompanion.custom(
          flags: appProxyEntries.flags.bitwiseAnd(Constant(~PkgFlag.forceDeselection.value)),
        ),
      );
      // romve extra items
      await (delete(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode) & tbl.flags.equals(0))).go();
    });
  }

  @override
  Future<int> clearAll({required AppProxyMode mode}) {
    return (delete(appProxyEntries)..where((tbl) => tbl.mode.equalsValue(mode))).go();
  }
}
