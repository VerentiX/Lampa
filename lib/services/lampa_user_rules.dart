import 'dart:convert';

import '../config/consts.dart';
import '../models/custom_rule.dart';
import 'builder/rule_set_registry.dart';
import 'settings_storage.dart';

/// Consumer-facing domain lists: through VPN vs bypass. Emitted as high-priority
/// inline rules (after sniff, before roscom/ads) so they win over presets.
class LampaUserRules {
  const LampaUserRules({
    this.throughVpn = const [],
    this.bypassVpn = const [],
  });

  final List<String> throughVpn;
  final List<String> bypassVpn;

  bool get isEmpty => throughVpn.isEmpty && bypassVpn.isEmpty;

  int get throughCount => throughVpn.length;
  int get bypassCount => bypassVpn.length;

  static const _key = 'lampa_user_rules';
  static const _vpnId = 'lampa-user-vpn';
  static const _directId = 'lampa-user-direct';

  /// After traffic-processing (num 0), before private-IP / ads (~950).
  static const _vpnNum = 5;
  static const _directNum = 6;

  static Future<LampaUserRules> load() async {
    final raw = await SettingsStorage.getVar(_key, '');
    if (raw.isEmpty) return const LampaUserRules();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const LampaUserRules();
      return LampaUserRules(
        throughVpn: _strings(j['vpn']),
        bypassVpn: _strings(j['direct']),
      );
    } catch (_) {
      return const LampaUserRules();
    }
  }

  Future<void> save() async {
    await SettingsStorage.setVar(
      _key,
      jsonEncode({'vpn': throughVpn, 'direct': bypassVpn}),
    );
    SettingsStorage.markConfigDirty();
  }

  /// Inline rules for tests / debug. Production emit uses [applyToRoute]
  /// so they sit after sniff but **before** roscom-category-ru (direct).
  List<CustomRule> toCustomRules() {
    final out = <CustomRule>[];
    if (throughVpn.isNotEmpty) {
      out.add(CustomRuleInline(
        id: _vpnId,
        name: 'lampa-user-vpn',
        enabled: true,
        orderNum: _vpnNum,
        domainSuffixes: throughVpn,
        outbound: 'vpn-1',
      ));
    }
    if (bypassVpn.isNotEmpty) {
      out.add(CustomRuleInline(
        id: _directId,
        name: 'lampa-user-direct',
        enabled: true,
        orderNum: _directNum,
        domainSuffixes: bypassVpn,
        outbound: kDirectOutboundTag,
      ));
    }
    return out;
  }

  /// Вставить доменные правила сразу после sniff. Иначе traffic-processing
  /// (num 0) уже отправит `.ru` в `direct-out` через roscom-category-ru —
  /// пользовательское «через VPN» никогда не сработает.
  void applyToRoute(RuleSetRegistry registry, {String proxyTag = 'vpn-1'}) {
    var at = registry.indexAfterPacketPrep();
    if (throughVpn.isNotEmpty) {
      final tag = registry.addRuleSet(_inlineSet(_vpnId, throughVpn));
      registry.insertRuleAt(at, {'rule_set': tag, 'outbound': proxyTag});
      at++;
    }
    if (bypassVpn.isNotEmpty) {
      final tag = registry.addRuleSet(_inlineSet(_directId, bypassVpn));
      registry.insertRuleAt(at, {
        'rule_set': tag,
        'outbound': kDirectOutboundTag,
      });
    }
  }

  /// DNS раньше ru-direct (Yandex на `.ru`), иначе резолв идёт мимо VPN.
  List<Map<String, dynamic>> toDnsRules(String serverTag) {
    if (throughVpn.isEmpty || serverTag.isEmpty) return const [];
    return [
      {
        'domain_suffix': throughVpn,
        'server': serverTag,
      },
    ];
  }

  static Map<String, dynamic> _inlineSet(String tag, List<String> hosts) => {
        'type': 'inline',
        'tag': tag,
        // domain_suffix: `reg.ru` matches `reg.ru`, `www.reg.ru`, `a.b.reg.ru`.
        'rules': [
          {'domain_suffix': hosts},
        ],
      };

  static String? normalizeDomain(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    s = s.replaceFirst(RegExp(r'^https?://'), '');
    s = s.replaceFirst(RegExp(r'^www\.'), '');
    final host = s.split('/').first.split('?').first.split('#').first;
    s = host.split(':').first.trim();
    s = s.replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (s.isEmpty || !s.contains('.')) return null;
    if (s.contains(' ')) return null;
    return s;
  }

  static List<String> _strings(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final e in raw) {
      final n = normalizeDomain('$e');
      if (n == null || seen.contains(n)) continue;
      seen.add(n);
      out.add(n);
    }
    return out;
  }
}
