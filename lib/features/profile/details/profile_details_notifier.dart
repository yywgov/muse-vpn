import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/details/profile_details_state.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_details_notifier.g.dart';

@riverpod
class ProfileDetailsNotifier extends _$ProfileDetailsNotifier with AppLogger {
  ProfileRepository get _profilesRepo => ref.read(profileRepositoryProvider).requireValue;

  @override
  Future<ProfileDetailsState> build(String id) async {
    final prof = (await _profilesRepo.getById(id).run()).match((l) => throw l, (prof) {
      // _originalProfile = prof;
      if (prof == null) {
        loggy.warning('profile with id: [$id] does not exist');
        throw const ProfileNotFoundFailure();
      }
      return prof;
    });
    // 穿云 1.1.1: the raw config editor is gone, so 保存 only changes the name / update settings
    // and writes the profile's own content back unchanged (it used to write the editor's
    // outbounds-only extract, which replaced the subscription until its next update).
    final profContent = await _profilesRepo.getRawConfig(id).run().then((e) => e.getOrElse((f) => ""));
    return ProfileDetailsState(
      loadingState: const AsyncData(null),
      profile: prof,
      configContent: profContent,
      isDetailsChanged: false,
    );
  }

  Future<T?> doAsync<T>(Future<T> Function() operation) async {
    if (state case AsyncData(value: final ProfileDetailsState data)) {
      state = AsyncData(data.copyWith(loadingState: const AsyncLoading()));
      final T? result = await operation();
      state = AsyncData(data.copyWith(loadingState: const AsyncData(null)));
      return result;
    }
    return null;
  }

  void setUserOverride(UserOverride userOverride) {
    if (state case AsyncData(value: final ProfileDetailsState data)) {
      state = AsyncData(
        data.copyWith(profile: data.profile.copyWith(userOverride: userOverride), isDetailsChanged: true),
      );
    }
  }

  Future<bool> save() async {
    bool success = false;
    if (state case AsyncData(:final value)) {
      if (value.loadingState case AsyncLoading()) return false;

      success =
          await doAsync<bool>(() async {
            final t = await ref.read(translationsProvider.future);
            return (await _profilesRepo.offlineUpdate(value.profile, value.configContent).run()).match(
              (l) async {
                await ref
                    .read(dialogNotifierProvider.notifier)
                    .showCustomAlertFromErr(
                      t.presentError(l, action: t.pages.profiles.msg.update.failureNamed(name: value.profile.name)),
                    );
                return false;
              },
              (r) {
                ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.profiles.msg.update.success);
                return true;
              },
            );
          }) ??
          false;
    }
    return success;
  }
}
