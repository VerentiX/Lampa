import 'dart:convert';

import 'package:http/http.dart' as http;

/// Connection probe: delay + exit IP / country (ipwho.is + fallbacks).
class LampaConnectionCheck {
  static const _ipApis = [
    'https://ipwho.is/',
    'https://ifconfig.co/json',
    'https://ipinfo.io/json',
  ];

  static Future<LampaConnectionResult> run() async {
    final sw = Stopwatch()..start();
    try {
      final ping = await http
          .get(Uri.parse('https://cp.cloudflare.com/generate_204'))
          .timeout(const Duration(seconds: 8));
      final delayMs = sw.elapsedMilliseconds;
      if (ping.statusCode != 204 && ping.statusCode != 200) {
        return LampaConnectionResult(
          ok: false,
          message: 'Нет ответа (${ping.statusCode})',
        );
      }
      final geo = await _fetchGeo();
      if (geo == null) {
        return LampaConnectionResult(
          ok: true,
          delayMs: delayMs,
          message: 'Соединено · ${delayMs} мс',
        );
      }
      final line = [
        if (geo.ip.isNotEmpty) geo.ip,
        if (geo.country.isNotEmpty) geo.country,
      ].join('\n');
      return LampaConnectionResult(
        ok: true,
        delayMs: delayMs,
        ip: geo.ip,
        country: geo.country,
        message: '$line\n${delayMs} мс',
      );
    } catch (e) {
      return LampaConnectionResult(ok: false, message: 'Ошибка: $e');
    }
  }

  static Future<_Geo?> _fetchGeo() async {
    for (final url in _ipApis) {
      try {
        final resp = await http
            .get(
              Uri.parse(url),
              headers: {'Accept': 'application/json', 'User-Agent': 'Lampa-Mobile'},
            )
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode != 200) continue;
        final j = jsonDecode(resp.body);
        if (j is! Map) continue;
        final map = j.cast<String, dynamic>();
        final ip = '${map['ip'] ?? map['query'] ?? ''}'.trim();
        final code = '${map['country_code'] ?? map['countryCode'] ?? map['country_iso'] ?? ''}'
            .trim();
        var name = '${map['country_name'] ?? ''}'.trim();
        if (name.isEmpty) {
          final c = '${map['country'] ?? ''}'.trim();
          if (c.length > 3) name = c;
        }
        final country = [
          if (name.isNotEmpty) name,
          if (code.isNotEmpty) '($code)',
        ].join(' ');
        if (ip.isNotEmpty || country.isNotEmpty) {
          return _Geo(ip: ip, country: country.trim());
        }
      } catch (_) {}
    }
    return null;
  }
}

class LampaConnectionResult {
  final bool ok;
  final int? delayMs;
  final String? ip;
  final String? country;
  final String message;
  const LampaConnectionResult({
    required this.ok,
    required this.message,
    this.delayMs,
    this.ip,
    this.country,
  });
}

class _Geo {
  final String ip;
  final String country;
  const _Geo({required this.ip, required this.country});
}
