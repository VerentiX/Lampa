import 'dart:async';

import 'app_log.dart';
import 'lampa_app_update.dart';
import 'lampa_download_progress.dart';
import 'rule_set_auto_updater.dart';
import 'settings_storage.dart';
import 'version_info.dart';

/// Lampa-side scheduler: interval checks + silent auto-download (app / geo)
/// with resume. Manual "check update" stays a dialog in the UI.
class LampaAutoUpdates {
  LampaAutoUpdates._();
  static final LampaAutoUpdates I = LampaAutoUpdates._();

  Timer? _timer;
  bool _appRunning = false;
  bool _geoRunning = false;
  RuleSetAutoUpdater? _geo;

  void bindGeo(RuleSetAutoUpdater updater) => _geo = updater;

  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 20), (_) {
      unawaited(tick());
    });
    unawaited(_seedAndTick());
  }

  Future<void> _seedAndTick() async {
    if (await SettingsStorage.peekLampaSubUpdateHours() == null) {
      await SettingsStorage.setLampaSubUpdateHours(12);
    }
    await tick();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    await maybeDownloadApp();
    await maybeUpdateGeo();
  }

  Future<void> maybeDownloadApp() async {
    if (_appRunning) return;
    final hours = await SettingsStorage.getLampaAppCheckHours();
    if (hours <= 0) return;
    final last = await SettingsStorage.getLampaLastAppCheck();
    final now = DateTime.now().toUtc();
    if (last != null && now.difference(last) < Duration(hours: hours)) {
      return;
    }
    _appRunning = true;
    try {
      final info = await LampaAppUpdate.I.check(
        localVersion: VersionInfo.I.version,
      );
      await SettingsStorage.setLampaLastAppCheck(now);
      if (info == null) return;
      AppLog.I.info('LampaAutoUpdates: app ${info.version} — auto download');
      final apk = await LampaAppUpdate.I.download(
        info,
        onProgress: (got, total) {
          if (!LampaDownloadProgress.I.isKindActive(LampaDownloadKind.app)) {
            LampaDownloadProgress.I.start(
              kind: LampaDownloadKind.app,
              label: 'Приложение ${info.version}',
              total: total,
            );
          }
          LampaDownloadProgress.I.update(
            kind: LampaDownloadKind.app,
            received: got,
            total: total,
          );
        },
      );
      if (apk != null) {
        await LampaAppUpdate.I.install(apk);
      }
    } catch (e) {
      AppLog.I.warning('LampaAutoUpdates.app: $e');
    } finally {
      LampaDownloadProgress.I.finish(LampaDownloadKind.app);
      _appRunning = false;
    }
  }

  Future<void> maybeUpdateGeo({bool force = false}) async {
    if (_geoRunning) return;
    final updater = _geo;
    if (updater == null) return;
    final hours = await SettingsStorage.getLampaGeoCheckHours();
    if (!force && hours <= 0) return;
    _geoRunning = true;
    try {
      await updater.checkNow(
        intervalHoursOverride: force ? 0 : hours,
        force: force,
        onProgress: (label, received, total, index, count) {
          if (!LampaDownloadProgress.I.isKindActive(LampaDownloadKind.geo)) {
            LampaDownloadProgress.I.start(
              kind: LampaDownloadKind.geo,
              label: 'Геофайлы',
            );
          }
          LampaDownloadProgress.I.update(
            kind: LampaDownloadKind.geo,
            label: count > 1 ? 'Геофайлы ($index/$count)' : label,
            received: received,
            total: total,
          );
        },
      );
    } catch (e) {
      AppLog.I.warning('LampaAutoUpdates.geo: $e');
    } finally {
      LampaDownloadProgress.I.finish(LampaDownloadKind.geo);
      _geoRunning = false;
    }
  }
}
