import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';
import 'version_info.dart';

/// Consumer (Lampa) app updates via GitHub Releases, with HTTP Range resume.
class LampaAppUpdate {
  LampaAppUpdate._();
  static final LampaAppUpdate I = LampaAppUpdate._();

  static const _api =
      'https://api.github.com/repos/VerentiX/Lampa/releases/latest';
  static const _ua = 'Lampa-Mobile-SB';
  static const _channel = MethodChannel('com.leadaxe.lxbox/lampa_update');

  Future<LampaUpdateInfo?> check({String? localVersion}) async {
    final local = localVersion ?? VersionInfo.I.version;
    try {
      final resp = await http
          .get(
            Uri.parse(_api),
            headers: {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': '$_ua/$local',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body);
      if (j is! Map<String, dynamic>) return null;
      final tag = '${j['tag_name'] ?? ''}'.replaceFirst(RegExp(r'^v'), '');
      if (tag.isEmpty || _compare(tag, local) <= 0) return null;
      final assets = (j['assets'] as List?) ?? const [];
      var supportedAbis = const <String>[];
      if (Platform.isAndroid) {
        supportedAbis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
      }
      final asset = selectLampaApkAsset(assets, supportedAbis);
      if (asset == null) return null;
      return LampaUpdateInfo(
        version: tag,
        notes: '${j['body'] ?? j['name'] ?? ''}'.trim(),
        downloadUrl: asset,
      );
    } catch (e) {
      AppLog.I.warning('LampaAppUpdate.check: $e');
      return null;
    }
  }

  /// Resume-friendly download into cache/`updates/Lampa-<ver>.apk.part`.
  Future<File?> download(
    LampaUpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = info.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final apk = File('${dir.path}/Lampa-$safe.apk');
    final part = File('${apk.path}.part');

    for (var attempt = 0; attempt < 4; attempt++) {
      final file = await _downloadAttempt(info, apk, part, onProgress);
      if (file != null) return file;
      if (attempt < 3) {
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    return null;
  }

  Future<File?> _downloadAttempt(
    LampaUpdateInfo info,
    File apk,
    File part,
    void Function(int received, int? total)? onProgress,
  ) async {
    var existing = 0;
    if (await part.exists()) existing = await part.length();

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(info.downloadUrl));
      req.headers.set(
        HttpHeaders.userAgentHeader,
        '$_ua/${VersionInfo.I.version}',
      );
      if (existing > 0) {
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      final resp = await req.close().timeout(const Duration(seconds: 60));
      if (resp.statusCode == 200 && existing > 0) {
        existing = 0;
        if (await part.exists()) await part.delete();
      }
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        AppLog.I.warning('LampaAppUpdate.download HTTP ${resp.statusCode}');
        return null;
      }
      final totalHeader = resp.contentLength;
      final total = totalHeader >= 0
          ? (resp.statusCode == 206 ? existing + totalHeader : totalHeader)
          : null;
      final sink = part.openWrite(mode: FileMode.append);
      var got = existing;
      onProgress?.call(got, total);
      await for (final chunk in resp) {
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(got, total);
      }
      await sink.close();
      if (got <= existing) return null;
      if (await apk.exists()) await apk.delete();
      await part.rename(apk.path);
      return apk;
    } catch (e) {
      AppLog.I.warning('LampaAppUpdate.download: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> install(File apk) async {
    try {
      final ok = await _channel.invokeMethod<bool>('installApk', {
        'path': apk.path,
      });
      return ok == true;
    } catch (e) {
      AppLog.I.warning('LampaAppUpdate.install: $e');
      return false;
    }
  }

  static int _compare(String a, String b) {
    final pa = a
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'\D.*'), '')) ?? 0)
        .toList();
    final pb = b
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'\D.*'), '')) ?? 0)
        .toList();
    for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }
}

/// Selects the smallest compatible release asset. GitHub doesn't expose an
/// architecture field, so official Lampa assets encode it in the filename.
String? selectLampaApkAsset(List<dynamic> assets, List<String> supportedAbis) {
  final apks = <String, String>{};
  for (final raw in assets) {
    if (raw is! Map) continue;
    final name = '${raw['name'] ?? ''}'.toLowerCase();
    final url = '${raw['browser_download_url'] ?? ''}';
    if (!name.endsWith('.apk') || url.isEmpty) continue;
    if (name.contains('arm64-v8a')) apks['arm64-v8a'] = url;
    if (name.contains('armeabi-v7a')) apks['armeabi-v7a'] = url;
    if (name.contains('x86_64')) apks['x86_64'] = url;
    if (RegExp(r'(^|[_-])x86([_.-]|$)').hasMatch(name) &&
        !name.contains('x86_64')) {
      apks['x86'] = url;
    }
    if (name.contains('universal')) apks['universal'] = url;
  }
  for (final abi in supportedAbis) {
    final match = apks[abi.toLowerCase()];
    if (match != null) return match;
  }
  return apks['universal'];
}

class LampaUpdateInfo {
  final String version;
  final String notes;
  final String downloadUrl;
  const LampaUpdateInfo({
    required this.version,
    required this.notes,
    required this.downloadUrl,
  });
}
