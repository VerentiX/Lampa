import 'dart:convert';
import 'package:http/http.dart' as http;
import 'settings_storage.dart';
import 'version_info.dart';

String? lampaSubId(String url) =>
    RegExp(r'/auto/([A-Za-z0-9_-]{6,128})/?').firstMatch(url)?.group(1);

class LampaPlan {
  final String id, title;
  final int days, trafficGb, priceRub;
  const LampaPlan(
    this.id,
    this.title,
    this.days,
    this.trafficGb,
    this.priceRub,
  );
  factory LampaPlan.fromJson(Map<String, dynamic> j) => LampaPlan(
        '${j['id'] ?? ''}',
        '${j['title'] ?? ''}',
        (j['days'] as num?)?.toInt() ?? 0,
        (j['trafficGb'] as num?)?.toInt() ?? 0,
        (j['priceRub'] as num?)?.toInt() ?? 0,
      );
}

class LampaSubscriptionInfo {
  final String title;
  final int daysLeft;
  final List<LampaPlan> plans;
  final List<String> methods;
  final bool paymentsEnabled;
  final bool allowTestPayment;
  final List<LampaOwnedPackage> packages;
  final double usedGb;
  final int? usedBytes;
  final double limitGb;

  const LampaSubscriptionInfo({
    required this.title,
    required this.daysLeft,
    required this.plans,
    required this.methods,
    required this.paymentsEnabled,
    required this.packages,
    this.allowTestPayment = false,
    this.usedGb = 0,
    this.usedBytes,
    this.limitGb = 0,
  });

  int get usedBytesResolved {
    if (usedBytes != null && usedBytes! > 0) return usedBytes!;
    if (usedGb > 0) return (usedGb * 1024 * 1024 * 1024).round();
    return 0;
  }

  int get limitBytesResolved {
    if (limitGb > 0) return (limitGb * 1024 * 1024 * 1024).round();
    return 0;
  }

  factory LampaSubscriptionInfo.fromJson(Map<String, dynamic> j) {
    final tariff = (j['tariff'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LampaSubscriptionInfo(
      title: '${tariff['title'] ?? 'Хаттабыч VPN'}',
      daysLeft: (tariff['daysLeft'] as num?)?.toInt() ?? 0,
      plans: ((j['plans'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LampaPlan.fromJson(e.cast<String, dynamic>()))
          .toList(),
      methods: ((j['paymentMethods'] as List?) ?? const ['sbp', 'usdt'])
          .map((e) => '$e')
          .toList(),
      paymentsEnabled: j['paymentsEnabled'] == true,
      allowTestPayment: j['allowTestPayment'] == true,
      packages: ((j['packages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => LampaOwnedPackage.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.active || e.upcoming)
          .toList(),
      usedGb: (tariff['usedGb'] as num?)?.toDouble() ?? 0,
      usedBytes: (tariff['usedBytes'] as num?)?.toInt(),
      limitGb: (tariff['limitGb'] as num?)?.toDouble() ??
          (tariff['trafficGb'] as num?)?.toDouble() ??
          0,
    );
  }
}

class LampaOwnedPackage {
  final String title;
  final int daysLeft, startsAt;
  final bool active, upcoming;
  const LampaOwnedPackage(
    this.title,
    this.daysLeft,
    this.startsAt,
    this.active,
    this.upcoming,
  );
  factory LampaOwnedPackage.fromJson(Map<String, dynamic> j) =>
      LampaOwnedPackage(
        '${j['title'] ?? ''}',
        (j['daysLeft'] as num?)?.toInt() ?? 0,
        (j['startsAt'] as num?)?.toInt() ?? 0,
        j['active'] == true,
        j['upcoming'] == true,
      );
}

class LampaBilling {
  static const _hosts = ['gw.zizmos.ru', 'sub.subhotig.buzz'];
  Future<Map<String, String>> _headers() async {
    var id = await SettingsStorage.getVar('lampa_device_id', '');
    if (id.isEmpty) {
      id = '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
      await SettingsStorage.setVar('lampa_device_id', id);
    }
    return {
      // Billing API keeps the legacy consumer-client identity. Only /auto/
      // subscription downloads use the worker selector Lampa-Mobile-SB.
      'User-Agent': 'Lampa-Mobile/${VersionInfo.I.version}',
      'X-Lampa-Device-Id': id,
      'Accept': 'application/json',
      'Connection': 'close',
    };
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    Object? last;
    for (final host in _hosts) {
      try {
        final headers = await _headers();
        final uri = Uri.https(host, path);
        final response = body == null
            ? await http
                .get(uri, headers: headers)
                .timeout(const Duration(seconds: 20))
            : await http
                .post(
                  uri,
                  headers: {...headers, 'Content-Type': 'application/json'},
                  body: jsonEncode(body),
                )
                .timeout(const Duration(seconds: 20));
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['ok'] == true) return decoded;
          last = decoded['error'] ?? 'HTTP ${response.statusCode}';
        }
      } catch (e) {
        last = e;
      }
    }
    throw Exception(last ?? 'Сервис оплаты недоступен');
  }

  Future<LampaSubscriptionInfo> subscription(String id) async =>
      LampaSubscriptionInfo.fromJson(
        await _request('/api/app/subscription/$id'),
      );

  Future<Uri> createPayment(
    String subId,
    LampaPlan plan,
    String method, {
    bool test = false,
  }) async {
    final j = await _request(
      '/api/app/payment',
      body: {
        'subId': subId,
        'planId': plan.id,
        'method': method,
        'test': test,
      },
    );
    final uri = Uri.tryParse('${j['payUrl'] ?? ''}');
    if (uri == null || !uri.hasScheme) {
      throw Exception('Сервис не вернул ссылку оплаты');
    }
    return uri;
  }
}
