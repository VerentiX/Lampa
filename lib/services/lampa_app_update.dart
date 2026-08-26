import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';
import 'version_info.dart';

/// Consumer (Lampa) app updates via hattabych.ru, with HTTP Range resume
/// (`.part` files) matching the old Lampa installer.
class LampaAppUpdate {
  LampaAppUpdate._();
  static final LampaAppUpdate I = LampaAppUpdate._();

  static const _api = 'https://hattabych.ru/api/app/latest';
  static const _ua = 'Lampa-Mobile';
  static const _channel = MethodChannel('com.leadaxe.lxbox/lampa_update');

  Future<LampaUpdateInfo?> check({String? localVersion}) async {
    final local = localVersion ?? VersionInfo.I.version;
    try {
      final resp = await http
          .get(
            Uri.parse(_api),
            headers: {
              'Accept': 'application/json',
              'User-Agent': '$_ua/$local',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(resp.body);
      if (j is! Map<String, dynamic> || j['ok'] != true) return null;
      final tag = '${j['tag'] ?? ''}'.replaceFirst(RegExp(r'^v'), '');
      if (tag.isEmpty || _compare(tag, local) <= 0) return null;
      final assets = (j['assets'] as List?) ?? const [];
      String? url;
      for (final a in assets) {
        if (a is! Map) continue;
        final arch = '${a['arch'] ?? ''}'.toLowerCase();
        if (arch == 'universal' || arch.contains('arm64')) {
          url = '${a['url'] ?? ''}';
          if (url.isNotEmpty) break;
        }
      }
      url ??= '${(j['apk'] as Map?)?['url'] ?? j['downloadUrl'] ?? ''}';
      if (url.isEmpty) return null;
      if (url.startsWith('/')) url = 'https://hattabych.ru$url';
      return LampaUpdateInfo(
        version: tag,
        notes: '${j['name'] ?? ''}',
        downloadUrl: url,
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
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/updates',
    );
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
      req.headers.set(HttpHeaders.userAgentHeader, '$_ua/${VersionInfo.I.version}');
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
    final pa = a.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'\D.*'), '')) ?? 0).toList();
    final pb = b.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'\D.*'), '')) ?? 0).toList();
    for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }
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
