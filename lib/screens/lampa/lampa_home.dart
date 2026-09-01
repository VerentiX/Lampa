import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/home_state.dart';
import '../../models/node_spec.dart';
import '../../models/tunnel_status.dart';
import '../../services/lampa_app_update.dart';
import '../../services/lampa_auto_updates.dart';
import '../../services/lampa_billing.dart';
import '../../services/lampa_connection_check.dart';
import '../../services/lampa_download_progress.dart';
import '../../services/lampa_user_rules.dart';
import '../../services/settings_storage.dart';
import '../../services/url_launcher.dart';
import '../../services/version_info.dart';
import '../qr_scan_screen.dart';
import 'lampa_ui.dart';
import 'lampa_update_settings_screen.dart';

class LampaHome extends StatefulWidget {
  final HomeState state;
  final List<SubscriptionEntry> subscriptions;
  final bool busy;
  final Future<void> Function()? onToggle;
  final Future<void> Function(String text) onImportText;
  final Future<bool> Function() onRefreshSubscription;
  final Future<void> Function()? onRefreshGeo;
  final VoidCallback? onOpenSplitTunnel;
  final VoidCallback? onOpenUserRules;
  final Future<void> Function(SubscriptionEntry entry)? onSelectSubscription;
  final Future<bool> Function(SubscriptionEntry entry)? onRefreshOne;
  final Future<void> Function(SubscriptionEntry entry)? onDeleteSubscription;
  final Future<void> Function()? onNetworkSettingsChanged;
  const LampaHome({
    super.key,
    required this.state,
    required this.subscriptions,
    required this.busy,
    required this.onToggle,
    required this.onImportText,
    required this.onRefreshSubscription,
    this.onRefreshGeo,
    this.onOpenSplitTunnel,
    this.onOpenUserRules,
    this.onSelectSubscription,
    this.onRefreshOne,
    this.onDeleteSubscription,
    this.onNetworkSettingsChanged,
  });
  @override
  State<LampaHome> createState() => _LampaHomeState();
}

class _LampaHomeState extends State<LampaHome> {
  final _billing = LampaBilling();
  final _connCheckKey = GlobalKey();
  Future<LampaSubscriptionInfo>? _info;
  String? _subId;
  bool _checking = false;
  String _checkText = 'Сначала подключитесь, чтобы проверить соединение';
  bool _updatingApp = false;

  bool get _working => widget.state.busy || widget.busy;

  String? _billingTitle;
  String _splitSummary = 'Все приложения через VPN';
  String _rulesSummary = 'Свои домены через VPN или мимо';
  String? _expandedSubId;

  List<SubscriptionEntry> get _urlSubs =>
      widget.subscriptions.where((e) => e.url.isNotEmpty).toList();

  SubscriptionEntry? get _activeSub {
    final urls = _urlSubs;
    if (urls.isEmpty) return null;
    for (final e in urls) {
      if (e.enabled) return e;
    }
    return urls.first;
  }

  /// Billing API id from `/auto/{id}` — derived live so a late-loaded
  /// subscription never leaves the panel stuck on a stale null `_subId`.
  String? get _resolvedSubId {
    final active = _activeSub;
    if (active == null) return null;
    return lampaSubId(active.url);
  }

  SubscriptionEntry? get _subEntry => _activeSub;

  static String _subsSig(List<SubscriptionEntry> subs) =>
      subs.map((e) => '${e.id}|${e.enabled}|${e.url}|${e.nodeCount}').join(';');

  String get _profileTitle {
    // Whole-connection name: urltest PROFILE_REMARK (e.g. "}{0ТТ@БЬ)Ч"),
    // then Profile-Title — never the selected leaf node.
    final active = _activeSub;
    if (active != null) {
      final fromSub = _connectionName(active);
      if (fromSub.isNotEmpty) return fromSub;
    }
    return 'Хаттабыч VPN';
  }

  /// Prefer urltest group remark (sing-box `tag` / AutoSelectSpec.label),
  /// then Profile-Title. Skip tariff and generic vpn/proxy/auto tags.
  String _connectionName(SubscriptionEntry e) {
    final remark = _urltestRemark(e);
    if (remark != null) return remark;
    final metaTitle = e.meta?.profileTitle?.trim() ?? '';
    for (final candidate in [metaTitle, e.name.trim(), e.displayName.trim()]) {
      if (candidate.isEmpty) continue;
      if (_looksLikeVpnTag(candidate)) continue;
      if (_isGenericGroupTag(candidate)) continue;
      if (_looksLikeTariff(candidate)) continue;
      if (_billingTitle != null &&
          candidate.toLowerCase() == _billingTitle!.toLowerCase()) {
        continue;
      }
      return candidate;
    }
    if (lampaSubId(e.url) != null) return 'Хаттабыч VPN';
    return '';
  }

  String? _urltestRemark(SubscriptionEntry e) {
    for (final n in e.list.nodes) {
      if (n is! AutoSelectSpec) continue;
      final label = n.label.trim();
      if (label.isEmpty) continue;
      if (_isGenericGroupTag(label) || _looksLikeVpnTag(label)) continue;
      if (_looksLikeTariff(label)) continue;
      return label;
    }
    return null;
  }

  bool _isGenericGroupTag(String s) {
    final t = s.trim().toLowerCase();
    return t == 'proxy' ||
        t == 'auto' ||
        t == 'urltest' ||
        t == 'selector' ||
        t == 'vpn';
  }

  bool _looksLikeTariff(String s) {
    final t = s.toLowerCase().replaceAll('·', ' ').replaceAll('•', ' ');
    if (_billingTitle != null &&
        t == _billingTitle!.toLowerCase().replaceAll('·', ' ')) {
      return true;
    }
    return t.contains('гб') ||
        t.contains('gb') ||
        t.contains('стандарт') ||
        t.contains('тариф') ||
        t.contains('плюс') ||
        t.contains('premium') ||
        RegExp(r'\d+\s*(gb|гб)').hasMatch(t);
  }

  bool _looksLikeVpnTag(String s) {
    final t = s.trim().toLowerCase();
    return t == 'vpn' ||
        RegExp(r'^vpn-\d+(-auto)?$').hasMatch(t) ||
        t.contains('-auto');
  }

  String _resolveNodeLabel(String tag) {
    if (_looksLikeVpnTag(tag)) return '';
    for (final e in widget.subscriptions) {
      for (final n in e.list.nodes) {
        final full = e.tagPrefix.isEmpty ? n.tag : '${e.tagPrefix} ${n.tag}';
        final compact = e.tagPrefix.isEmpty ? n.tag : '${e.tagPrefix}${n.tag}';
        if (tag == n.tag ||
            tag == full ||
            tag == compact ||
            tag.endsWith(' ${n.tag}') ||
            tag.endsWith('-${n.tag}') ||
            tag.endsWith(n.tag)) {
          final label = n.label.trim();
          if (label.isNotEmpty &&
              !_looksLikeVpnTag(label) &&
              !_looksLikeTariff(label)) {
            return label;
          }
        }
      }
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _reload();
    _loadSplitSummary();
    _loadRulesSummary();
    _syncConnectionRemark();
    LampaDownloadProgress.I.addListener(_onDownloadProgress);
    LampaAutoUpdates.I.start();
  }

  @override
  void dispose() {
    LampaDownloadProgress.I.removeListener(_onDownloadProgress);
    super.dispose();
  }

  void _onDownloadProgress() {
    if (mounted) setState(() {});
  }

  Future<void> _syncConnectionRemark() async {
    final active = _activeSub;
    if (active == null) return;
    final name = _connectionName(active);
    if (name.isEmpty) return;
    await SettingsStorage.setVar('lampa_connection_remark', name);
  }

  Future<void> _loadSplitSummary() async {
    final tun = await SettingsStorage.getTunApps();
    if (!mounted) return;
    final n = tun.packages.length;
    setState(() {
      _splitSummary = switch (tun.mode) {
        'deny' when n > 0 => 'Обход: $n прил.',
        'allow' when n > 0 => 'Через VPN: $n прил.',
        _ => 'Все приложения через VPN',
      };
    });
  }

  Future<void> _loadRulesSummary() async {
    final rules = await LampaUserRules.load();
    if (!mounted) return;
    setState(() {
      final n = rules.throughCount + rules.bypassCount;
      _rulesSummary = n == 0
          ? 'Свои домены через VPN или мимо'
          : 'Через VPN: ${rules.throughCount} · Мимо: ${rules.bypassCount}';
    });
  }

  @override
  void didUpdateWidget(covariant LampaHome old) {
    super.didUpdateWidget(old);
    // Identity `!=` misses in-place list updates; compare url/id signature.
    if (_subsSig(old.subscriptions) != _subsSig(widget.subscriptions)) {
      _reload();
    }
    _loadSplitSummary();
    _loadRulesSummary();
    if (!widget.state.tunnelUp && old.state.tunnelUp) {
      _checkText = 'Сначала подключитесь, чтобы проверить соединение';
    } else if (widget.state.tunnelUp && !old.state.tunnelUp) {
      _checkText = 'Соединено — нажмите для проверки';
    }
  }

  void _reload({bool scheduleRebuild = false}) {
    final id = _resolvedSubId;
    if (id == _subId && (id == null || _info != null)) return;
    _subId = id;
    if (id == null) {
      _info = null;
      _billingTitle = null;
    } else {
      final future = _billing.subscription(id);
      _info = future;
      future
          .then((info) {
            if (!mounted || _subId != id) return;
            setState(() => _billingTitle = info.title);
          })
          .catchError((_) {});
    }
    if (scheduleRebuild && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final up = widget.state.tunnelUp;
    return Scaffold(
      backgroundColor: LampaUi.bgDeep,
      body: Stack(
        children: [
          const Positioned.fill(child: _CosmicBackground()),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Ещё',
                        onPressed: _showOverflowMenu,
                        icon: const Icon(Icons.more_vert, color: LampaUi.link),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Добавить подписку',
                        onPressed: _showImportMenu,
                        icon: const Icon(Icons.add, color: LampaUi.accent),
                      ),
                      IconButton(
                        tooltip: 'Импорт из буфера',
                        onPressed: _importClipboard,
                        icon: const Icon(
                          Icons.content_paste,
                          color: LampaUi.crt,
                        ),
                      ),
                      const _LampaDownloadBadge(),
                      Padding(
                        padding: const EdgeInsets.only(right: 10, left: 2),
                        child: Text(
                          'v${VersionInfo.I.version}',
                          style: LampaUi.mono.copyWith(
                            fontSize: 11,
                            color: LampaUi.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      Transform.translate(
                        offset: const Offset(0, 18),
                        child: _PowerDock(
                          connecting:
                              widget.state.tunnel == TunnelStatus.connecting,
                          connected:
                              up ||
                              widget.state.tunnel == TunnelStatus.stopping,
                          onTap: _working ? null : widget.onToggle,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        up ? '» В СЕТИ «' : '» НЕ В СЕТИ «',
                        style: LampaUi.mono.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: up ? LampaUi.crt : LampaUi.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _profileTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: LampaUi.mono.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: LampaUi.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (widget.onOpenSplitTunnel != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () {
                              widget.onOpenSplitTunnel!();
                              Future<void>.delayed(
                                const Duration(milliseconds: 600),
                                _loadSplitSummary,
                              );
                            },
                            child: _GlassCard(
                              child: Row(
                                children: [
                                  _chip(Icons.alt_route),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '>> разд. туннель',
                                          style: LampaUi.mono.copyWith(
                                            fontSize: 12,
                                            color: LampaUi.link,
                                            fontWeight: FontWeight.w700,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: LampaUi.link,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _splitSummary,
                                          style: LampaUi.mono.copyWith(
                                            fontSize: 11,
                                            color: LampaUi.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Text(
                                    '»',
                                    style: TextStyle(
                                      color: LampaUi.accent,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (widget.onOpenUserRules != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () {
                              widget.onOpenUserRules!();
                              Future<void>.delayed(
                                const Duration(milliseconds: 600),
                                _loadRulesSummary,
                              );
                            },
                            child: _GlassCard(
                              child: Row(
                                children: [
                                  _chip(Icons.rule),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '>> мои правила',
                                          style: LampaUi.mono.copyWith(
                                            fontSize: 12,
                                            color: LampaUi.link,
                                            fontWeight: FontWeight.w700,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: LampaUi.link,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _rulesSummary,
                                          style: LampaUi.mono.copyWith(
                                            fontSize: 11,
                                            color: LampaUi.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Text(
                                    '»',
                                    style: TextStyle(
                                      color: LampaUi.accent,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Material(
                        color: const Color(0x28ff9900),
                        child: InkWell(
                          onTap: _working ? null : _refreshSubscription,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: LampaUi.accent,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.refresh,
                                  size: 18,
                                  color: LampaUi.accent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '[ обновить подписку ]',
                                  style: LampaUi.mono.copyWith(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: LampaUi.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: LampaUi.crt,
                    onRefresh: _pullRefresh,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                          child: Row(
                            children: [
                              Text(
                                ':: гостевая ::',
                                style: LampaUi.mono.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                  color: LampaUi.accent,
                                ),
                              ),
                              const Spacer(),
                              if (_urlSubs.length > 1)
                                Text(
                                  'выберите',
                                  style: LampaUi.mono.copyWith(
                                    fontSize: 11,
                                    color: LampaUi.muted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _subscriptionCard(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runConnectionCheck() async {
    setState(() {
      _checking = true;
      _checkText = 'Проверка…';
    });
    final r = await LampaConnectionCheck.run();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checkText = r.message;
    });
  }

  Future<void> _pullRefresh() async {
    await _refreshSubscription();
    await widget.onRefreshGeo?.call();
  }

  Future<void> _showOverflowMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xff1a1208),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onOpenSplitTunnel != null)
              ListTile(
                leading: const Icon(Icons.alt_route),
                title: const Text('Раздельное туннелирование'),
                subtitle: const Text('Приложения через VPN / мимо VPN'),
                onTap: () => Navigator.pop(context, 'split'),
              ),
            if (widget.onOpenUserRules != null)
              ListTile(
                leading: const Icon(Icons.rule),
                title: const Text('Мои правила'),
                subtitle: const Text('Домены через VPN или мимо'),
                onTap: () => Navigator.pop(context, 'rules'),
              ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('DoH и Resolve'),
              subtitle: const Text('DNS приложений и стратегия резолва'),
              onTap: () => Navigator.pop(context, 'network'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Обновить подписку и гео'),
              onTap: () => Navigator.pop(context, 'refresh_all'),
            ),
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Проверить обновление'),
              onTap: () => Navigator.pop(context, 'update'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Автообновление'),
              subtitle: const Text('Подписка, приложение, геофайлы'),
              onTap: () => Navigator.pop(context, 'intervals'),
            ),
            if (_subEntry?.url.isNotEmpty == true)
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Ссылка подписки'),
                onTap: () => Navigator.pop(context, 'sub_url'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'split':
        widget.onOpenSplitTunnel?.call();
      case 'rules':
        widget.onOpenUserRules?.call();
        Future<void>.delayed(
          const Duration(milliseconds: 600),
          _loadRulesSummary,
        );
      case 'network':
        await _showNetworkSettings();
      case 'refresh_all':
        await _pullRefresh();
      case 'update':
        await _checkAppUpdate(force: true);
      case 'intervals':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const LampaUpdateSettingsScreen(),
          ),
        );
      case 'sub_url':
        await _showSubscriptionUrl();
    }
  }

  Future<void> _showSubscriptionUrl() async {
    final url = _subEntry?.url;
    if (url == null || url.isEmpty) return;
    await LampaUi.dialog<void>(
      context: context,
      title: const Text('Ссылка подписки'),
      content: SelectableText(
        url,
        style: const TextStyle(color: LampaUi.onSurface),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) Navigator.pop(context);
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(LampaUi.snack('Ссылка скопирована'));
            }
          },
          child: const Text('Копировать'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }

  Future<void> _checkAppUpdate({required bool force}) async {
    if (_updatingApp) return;
    final info = await LampaAppUpdate.I.check(
      localVersion: VersionInfo.I.version,
    );
    if (!mounted) return;
    if (info == null) {
      if (force) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(LampaUi.snack('Обновлений нет'));
      }
      return;
    }
    final go = await LampaUi.dialog<bool>(
      context: context,
      title: Text('Обновление ${info.version}'),
      content: Text(
        info.notes.isEmpty
            ? 'Доступна новая версия. Загрузить и установить?'
            : info.notes,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Позже'),
        ),
        FilledButton(
          style: LampaUi.primaryButton,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Скачать'),
        ),
      ],
    );
    if (go != true || !mounted) return;
    setState(() => _updatingApp = true);
    final messenger = ScaffoldMessenger.of(context);
    File? apk;
    try {
      apk = await LampaAppUpdate.I.download(
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
    } finally {
      LampaDownloadProgress.I.finish(LampaDownloadKind.app);
    }
    if (!mounted) return;
    setState(() => _updatingApp = false);
    if (apk == null) {
      messenger.showSnackBar(LampaUi.snack('Не удалось загрузить обновление'));
      return;
    }
    final ok = await LampaAppUpdate.I.install(apk);
    if (!ok && mounted) {
      messenger.showSnackBar(LampaUi.snack('Не удалось открыть установщик'));
    }
  }

  Future<void> _showImportMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Импорт из буфера'),
              onTap: () => Navigator.pop(context, 'clipboard'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Сканировать QR-код'),
              onTap: () => Navigator.pop(context, 'qr'),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Ввести вручную'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
          ],
        ),
      ),
    );
    if (action == 'clipboard') await _importClipboard();
    if (action == 'qr') await _scanQr();
    if (action == 'manual') await _manualImport();
  }

  Future<void> _importClipboard() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(LampaUi.snack('В буфере обмена нет ссылки подписки'));
      }
      return;
    }
    await widget.onImportText(text);
  }

  Future<void> _scanQr() async {
    final outcome = await Navigator.push<ScanOutcome>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (outcome is ScannedCode) await widget.onImportText(outcome.value);
  }

  Future<void> _manualImport() async {
    final controller = TextEditingController();
    final text = await LampaUi.dialog<String>(
      context: context,
      title: const Text('Добавить подписку'),
      content: TextField(
        controller: controller,
        minLines: 3,
        maxLines: 8,
        autofocus: true,
        style: const TextStyle(color: LampaUi.onSurface),
        decoration: const InputDecoration(
          hintText: 'Вставьте ссылку подписки Хаттабыч',
          hintStyle: TextStyle(color: LampaUi.muted),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: LampaUi.primaryButton,
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Добавить'),
        ),
      ],
    );
    controller.dispose();
    if (text != null && text.isNotEmpty) await widget.onImportText(text);
  }

  Future<void> _showNetworkSettings() async {
    var dns = await SettingsStorage.getVar('dns_final', 'cloudflare_doh');
    if (dns != 'google_doh') dns = 'cloudflare_doh';
    if (!mounted) return;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xff1a1208),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ListTile(
                      title: Text(
                        'DoH и Resolve',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'DoH приложений (через VPN)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0x99ffffff),
                        ),
                      ),
                    ),
                    RadioListTile<String>(
                      value: 'cloudflare_doh',
                      groupValue: dns,
                      activeColor: const Color(0xffff8f00),
                      title: const Text('DoH 1.1.1.1'),
                      subtitle: const Text('Cloudflare через VPN'),
                      onChanged: (v) => setSheet(() => dns = v!),
                    ),
                    RadioListTile<String>(
                      value: 'google_doh',
                      groupValue: dns,
                      activeColor: const Color(0xffff8f00),
                      title: const Text('DoH 8.8.8.8'),
                      subtitle: const Text('Google через VPN'),
                      onChanged: (v) => setSheet(() => dns = v!),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        'Маршрутизация по доменам и IP включена автоматически.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0x99ffffff),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: FilledButton(
                        style: LampaUi.primaryButton,
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Сохранить'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (applied != true) return;
    await SettingsStorage.setVar('dns_final', dns, flush: false);
    await SettingsStorage.setVar('resolve_enabled', 'true');
    await widget.onNetworkSettingsChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(LampaUi.snack('Настройки сети сохранены'));
  }

  Future<void> _refreshSubscription() async {
    await widget.onRefreshSubscription();
    await _syncConnectionRemark();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(LampaUi.snack('Подписка обновлена'));
    if (_subId == null) return;
    final future = _billing.subscription(_subId!);
    setState(() => _info = future);
    try {
      final info = await future;
      if (mounted) setState(() => _billingTitle = info.title);
    } catch (_) {}
  }

  Widget _chip(IconData icon) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: const Color(0x221a9944),
      border: Border.all(color: LampaUi.crtDim, width: 1),
    ),
    child: Icon(icon, size: 18, color: LampaUi.crt),
  );

  Widget _subscriptionCard() {
    final subs = _urlSubs;
    if (subs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LampaUi.panel,
          border: Border.all(color: LampaUi.border, width: 2),
        ),
        child: Text(
          'гостевая пуста. добавьте /auto/ ссылку сверху.',
          style: LampaUi.mono.copyWith(color: LampaUi.muted, fontSize: 12),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < subs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _oneSubscriptionCard(subs[i]),
        ],
      ],
    );
  }

  Widget _oneSubscriptionCard(SubscriptionEntry entry) {
    final multi = _urlSubs.length > 1;
    final active =
        identical(entry, _activeSub) ||
        (entry.enabled && entry.id == _activeSub?.id);
    final title = _connectionName(entry);
    final shown = title.isNotEmpty ? title : 'Хаттабыч VPN';
    final nodes = entry.nodeCount;
    final expandedId = _expandedSubId ?? (active ? entry.id : null);
    final expanded = expandedId == entry.id;
    final highlight = multi && active;
    final edge = highlight ? LampaUi.crt : LampaUi.border;

    return Container(
      decoration: BoxDecoration(
        color: highlight ? const Color(0x181a9944) : LampaUi.panel,
        border: Border.all(color: edge, width: highlight ? 2 : 1),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              if (!active && widget.onSelectSubscription != null) {
                await widget.onSelectSubscription!(entry);
              }
              setState(() {
                _expandedSubId = expanded && active ? null : entry.id;
              });
              _reload();
            },
            child: SizedBox(
              height: 50,
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: AnimatedRotation(
                      turns: expanded ? 0 : -.25,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        size: 22,
                        color: highlight ? LampaUi.crt : LampaUi.link,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shown,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LampaUi.mono.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: highlight ? LampaUi.crt : LampaUi.link,
                            decoration: TextDecoration.underline,
                            decorationColor: highlight
                                ? LampaUi.crt
                                : LampaUi.link,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          [
                            if (nodes > 0) '$nodes конф.',
                            if (highlight) 'ACTIVE',
                            if (nodes == 0 && !highlight) 'выбрать',
                          ].join(' · '),
                          style: LampaUi.mono.copyWith(
                            fontSize: 10,
                            color: LampaUi.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Действия',
                    color: LampaUi.bg,
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.more_horiz,
                      color: LampaUi.accent,
                      size: 20,
                    ),
                    onSelected: (action) => _onSubMenuAction(action, entry),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'copy',
                        child: Text('Скопировать ссылку'),
                      ),
                      PopupMenuItem(
                        value: 'refresh',
                        child: Text('Обновить подписку'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Удалить подписку'),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: expanded && active
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: _billingPanel(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _onSubMenuAction(String action, SubscriptionEntry entry) async {
    switch (action) {
      case 'copy':
        final url = entry.url;
        if (url.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: url));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(LampaUi.snack('Ссылка скопирована'));
      case 'refresh':
        if (widget.onRefreshOne != null) {
          await widget.onRefreshOne!(entry);
        } else {
          await widget.onRefreshSubscription();
          await _syncConnectionRemark();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(LampaUi.snack('Подписка обновлена'));
        final id = lampaSubId(entry.url);
        if (id != null) {
          final future = _billing.subscription(id);
          setState(() {
            _subId = id;
            _info = future;
          });
          try {
            final info = await future;
            if (mounted) setState(() => _billingTitle = info.title);
          } catch (_) {}
        }
      case 'delete':
        final ok = await LampaUi.dialog<bool>(
          context: context,
          title: const Text('Удалить подписку?'),
          content: Text(
            'Подписка «${_connectionName(entry).isEmpty ? 'Хаттабыч VPN' : _connectionName(entry)}» будет удалена с устройства.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffc44a3a),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить'),
            ),
          ],
        );
        if (ok == true && widget.onDeleteSubscription != null) {
          await widget.onDeleteSubscription!(entry);
        }
    }
  }

  Widget _billingPanel() {
    final id = _resolvedSubId;
    // Late-loaded /auto/ id: kick billing fetch if cache lagged behind UI.
    if (id != null && (id != _subId || _info == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload(scheduleRebuild: true);
      });
    }
    if (id == null) {
      final hasSub = _activeSub != null;
      return _statsBox(
        Text(
          hasSub
              ? 'VPN-конфиг есть, но это не ссылка Хаттабыч (/auto/…). Статистика и оплата здесь недоступны.'
              : 'Нет ссылки подписки Хаттабыч. Добавьте /auto/… или установите поверх старой Lampa, чтобы перенести её.',
          style: const TextStyle(color: Color(0xccffffff), height: 1.35),
        ),
      );
    }
    return FutureBuilder<LampaSubscriptionInfo>(
      future: _info ?? _billing.subscription(id),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _statsBox(
            const Center(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return _statsBox(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Не удалось загрузить данные подписки'),
                TextButton(
                  onPressed: () {
                    final future = _billing.subscription(id);
                    setState(() {
                      _subId = id;
                      _info = future;
                    });
                    future
                        .then((info) {
                          if (mounted)
                            setState(() => _billingTitle = info.title);
                        })
                        .catchError((_) {});
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          );
        }
        final info = snap.data!;
        final entry = _subEntry;
        final usedFromBilling = info.usedBytesResolved;
        final limitFromBilling = info.limitBytesResolved;
        final usedFromMeta =
            (entry?.uploadBytes ?? 0) + (entry?.downloadBytes ?? 0);
        final limitFromMeta = entry?.totalBytes ?? 0;
        final used = usedFromBilling > 0 ? usedFromBilling : usedFromMeta;
        final limit = limitFromBilling > 0 ? limitFromBilling : limitFromMeta;
        final daysOk = info.daysLeft > 0;
        return _statsBox(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      info.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LampaUi.mono.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: LampaUi.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    daysOk ? 'счётчик: ${info.daysLeft} дн.' : 'EXPIRED',
                    style: LampaUi.mono.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: daysOk ? LampaUi.crt : LampaUi.warn,
                    ),
                  ),
                ],
              ),
              if (used > 0 || limit > 0) ...[
                const SizedBox(height: 8),
                _trafficRow(used: used, limit: limit),
              ],
              if (info.packages.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: info.packages.map(_packageChip).toList(),
                ),
              ],
              if (info.paymentsEnabled && info.plans.isNotEmpty) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: LampaUi.link,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _choosePlan(info),
                    child: Text(
                      '[ продлить ]',
                      style: LampaUi.mono.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                        decorationColor: LampaUi.link,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _trafficRow({required int used, required int limit}) {
    final pct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final usedGb = used / (1024 * 1024 * 1024);
    final limitGb = limit / (1024 * 1024 * 1024);
    final usedLabel = usedGb >= 10
        ? usedGb.toStringAsFixed(0)
        : usedGb.toStringAsFixed(1);
    final limitLabel = limit <= 0
        ? '∞'
        : (limitGb >= 10
              ? limitGb.toStringAsFixed(0)
              : limitGb.toStringAsFixed(1));
    final barColor = pct > 0.9
        ? LampaUi.warn
        : pct > 0.7
        ? LampaUi.accent
        : LampaUi.crt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'трафик: $usedLabel/$limitLabel ГБ',
              style: LampaUi.mono.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: LampaUi.onSurface,
              ),
            ),
            const Spacer(),
            if (limit > 0)
              Text(
                '${(pct * 100).round()}%',
                style: LampaUi.mono.copyWith(
                  fontSize: 10,
                  color: LampaUi.muted,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: limit > 0 ? pct : null,
          minHeight: 6,
          backgroundColor: const Color(0x33224466),
          color: barColor,
        ),
      ],
    );
  }

  Widget _packageChip(LampaOwnedPackage package) {
    final starts = package.startsAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(package.startsAt * 1000)
        : null;
    final startText = starts == null
        ? null
        : '${starts.day.toString().padLeft(2, '0')}.${starts.month.toString().padLeft(2, '0')}';
    final days = package.daysLeft > 0 ? '${package.daysLeft}д' : null;
    final parts = <String>[
      package.shortLabel,
      if (package.active && days != null) days,
      if (!package.active && startText != null) 'с $startText',
      if (!package.active && days != null) days,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: package.active
            ? const Color(0x2233ff66)
            : const Color(0x1466b3ff),
        border: Border.all(color: package.active ? LampaUi.crt : LampaUi.link),
      ),
      child: Text(
        parts.join(' · '),
        style: LampaUi.mono.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: package.active ? LampaUi.crt : LampaUi.link,
        ),
      ),
    );
  }

  Widget _statsBox(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      color: const Color(0xff080c16),
      border: Border.all(color: const Color(0x5544aaff)),
    ),
    child: child,
  );
  Future<void> _choosePlan(LampaSubscriptionInfo info) async {
    final plan = await showModalBottomSheet<LampaPlan>(
      context: context,
      backgroundColor: LampaUi.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: LampaUi.border, width: 2),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                ':: тариф ::',
                style: LampaUi.mono.copyWith(
                  fontWeight: FontWeight.w800,
                  color: LampaUi.accent,
                ),
              ),
            ),
            ...info.plans.map(
              (p) => ListTile(
                title: Text(
                  '${p.trafficGb} ГБ',
                  style: LampaUi.mono.copyWith(
                    color: LampaUi.link,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                    decorationColor: LampaUi.link,
                  ),
                ),
                subtitle: Text(
                  '${p.days} дн. · ${p.title}',
                  style: LampaUi.mono.copyWith(
                    color: LampaUi.muted,
                    fontSize: 12,
                  ),
                ),
                trailing: Text(
                  '${p.priceRub} ₽',
                  style: LampaUi.mono.copyWith(
                    fontWeight: FontWeight.w800,
                    color: LampaUi.accent,
                  ),
                ),
                onTap: () => Navigator.pop(context, p),
              ),
            ),
          ],
        ),
      ),
    );
    if (plan == null || !mounted) return;
    final method = await showModalBottomSheet<({String method, bool test})>(
      context: context,
      backgroundColor: LampaUi.bg,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Способ оплаты')),
            if (info.methods.contains('sbp'))
              ListTile(
                leading: const Icon(Icons.account_balance),
                title: const Text('СБП'),
                subtitle: const Text('Через ваш банк, за несколько секунд'),
                onTap: () =>
                    Navigator.pop(context, (method: 'sbp', test: false)),
              ),
            if (info.methods.contains('usdt'))
              ListTile(
                leading: const Icon(Icons.currency_bitcoin),
                title: const Text('USDT / Crypto'),
                subtitle: const Text('Tether и другие криптовалюты'),
                onTap: () =>
                    Navigator.pop(context, (method: 'usdt', test: false)),
              ),
            if (info.allowTestPayment && info.methods.contains('sbp'))
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('Тестовая оплата СБП'),
                subtitle: const Text('Только для администратора'),
                onTap: () =>
                    Navigator.pop(context, (method: 'sbp', test: true)),
              ),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return;
    try {
      await UrlLauncher.open(
        (await _billing.createPayment(
          _subId!,
          plan,
          method.method,
          test: method.test,
        )).toString(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(LampaUi.snack('Ошибка оплаты: $e'));
      }
    }
  }
}

class _LampaDownloadBadge extends StatelessWidget {
  const _LampaDownloadBadge();

  @override
  Widget build(BuildContext context) {
    final progress = LampaDownloadProgress.I;
    if (!progress.active) return const SizedBox.shrink();
    final fraction = progress.overallFraction;
    final percent = fraction == null ? null : (fraction * 100).round();
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _showSheet(context),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 2.6,
                  backgroundColor: const Color(0x33ffab40),
                  color: LampaUi.accent,
                ),
              ),
              Text(
                percent == null ? '…' : '$percent',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Color(0xffffe0a8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _showSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: LampaUi.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ListenableBuilder(
        listenable: LampaDownloadProgress.I,
        builder: (context, _) {
          final jobs = LampaDownloadProgress.I.jobs;
          if (jobs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Text(
                'Ничего не скачивается',
                style: TextStyle(color: LampaUi.muted),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Скачивается',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: LampaUi.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                for (final job in jobs) ...[
                  Row(
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          value: job.fraction,
                          strokeWidth: 2.4,
                          backgroundColor: const Color(0x33ffab40),
                          color: LampaUi.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          job.label,
                          style: const TextStyle(color: LampaUi.onSurface),
                        ),
                      ),
                      Text(
                        job.percent == null ? '…' : '${job.percent}%',
                        style: const TextStyle(
                          color: LampaUi.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: LampaUi.panel,
      border: Border.all(color: LampaUi.border, width: 1),
    ),
    child: child,
  );
}

class _CosmicBackground extends StatelessWidget {
  const _CosmicBackground();
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: LampaUi.bgDeep,
    child: CustomPaint(painter: _RunetPainter()),
  );
}

/// Starfield + CRT scanlines — personal homepage / dial-up night vibe.
class _RunetPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final glow = Offset(s.width * .5, s.height * .2);
    c.drawCircle(
      glow,
      s.width * .95,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x281a9944), Color(0x00000000)],
        ).createShader(Rect.fromCircle(center: glow, radius: s.width * .95)),
    );
    final star = Paint()..color = const Color(0x66e8f0ff);
    final rnd = [
      0.12,
      0.08,
      0.77,
      0.14,
      0.33,
      0.22,
      0.91,
      0.18,
      0.55,
      0.31,
      0.18,
      0.44,
      0.68,
      0.39,
      0.42,
      0.52,
      0.85,
      0.48,
      0.07,
      0.61,
      0.63,
      0.71,
      0.29,
      0.79,
      0.94,
      0.66,
      0.48,
      0.88,
      0.16,
      0.93,
    ];
    for (var i = 0; i < rnd.length; i += 2) {
      final x = rnd[i] * s.width;
      final y = rnd[i + 1] * s.height;
      final r = (i % 5 == 0) ? 1.6 : 0.9;
      c.drawCircle(Offset(x, y), r, star);
    }
    final scan = Paint()..color = const Color(0x0affffff);
    for (var y = 0.0; y < s.height; y += 3) {
      c.drawRect(Rect.fromLTWH(0, y, s.width, 1), scan);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PowerDock extends StatefulWidget {
  final bool connecting, connected;
  final Future<void> Function()? onTap;
  const _PowerDock({
    required this.connecting,
    required this.connected,
    required this.onTap,
  });
  @override
  State<_PowerDock> createState() => _PowerDockState();
}

class _PowerDockState extends State<_PowerDock> with WidgetsBindingObserver {
  MethodChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_channel == null) return;
    if (state == AppLifecycleState.resumed) {
      _channel?.invokeMethod<void>('resume');
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _channel?.invokeMethod<void>('pause');
    }
  }

  @override
  void didUpdateWidget(covariant _PowerDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connecting != widget.connecting ||
        oldWidget.connected != widget.connected) {
      _pushState();
    }
  }

  Future<void> _pushState() async {
    // Only push visual state — avoid resume/bringToFront on every rebuild (lag).
    await _channel?.invokeMethod<void>('state', {
      'connecting': widget.connecting,
      'connected': widget.connected,
      'animate': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox(
        width: 248,
        height: 248,
        child: Center(child: Icon(Icons.shield, size: 112)),
      );
    }
    return RepaintBoundary(
      child: SizedBox(
        width: 248,
        height: 248,
        child: AndroidView(
          viewType: 'com.leadaxe.lxbox/lampa_power',
          creationParams: {
            'connecting': widget.connecting,
            'connected': widget.connected,
            'animate': true,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: (id) {
            final channel = MethodChannel('com.leadaxe.lxbox/lampa_power/$id');
            channel.setMethodCallHandler((call) async {
              if (call.method == 'tap') await widget.onTap?.call();
            });
            _channel = channel;
            _pushState();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}

// Kept temporarily as a non-Android preview fallback; Android release/debug
// uses the original Kotlin ShieldDockView above.
// ignore: unused_element
class _ManualPowerDock extends StatelessWidget {
  final Animation<double> motion, blend;
  final bool busy, animations;
  final Future<void> Function()? onTap;
  const _ManualPowerDock({
    required this.motion,
    required this.blend,
    required this.busy,
    required this.animations,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([motion, blend]),
    builder: (_, _) {
      final pulse = animations
          ? .78 + .22 * math.sin(motion.value * math.pi * 2).abs()
          : 1.0;
      final gradient = blend.value > .5
          ? const RadialGradient(
              center: Alignment(0, -.16),
              colors: [Color(0xff1a3a55), Color(0xff152840), Color(0xff0e1a2c)],
            )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff2e2348), Color(0xff1a2034), Color(0xff12182a)],
            );
      return SizedBox(
        width: 248,
        height: 248,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: blend.value * pulse,
              child: Container(
                width: 236,
                height: 236,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0x6600f5d4),
                      Color(0x3300b4d8),
                      Color(0x0000b4d8),
                    ],
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: onTap,
              child: AnimatedScale(
                scale: busy ? .98 : 1,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  width: 192,
                  height: 192,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: gradient,
                    border: Border.all(
                      width: 3,
                      color: Color.lerp(
                        const Color(0x88c8e8ff),
                        const Color(0xcc7ef5e0),
                        blend.value,
                      )!,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: CustomPaint(
                      painter: _ShieldPainter(
                        angle: motion.value * math.pi * 2,
                        power: blend.value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (busy)
              Transform.rotate(
                angle: motion.value * math.pi * 2,
                child: Container(
                  width: 184,
                  height: 184,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border(
                      top: BorderSide(width: 5, color: Color(0xffb8fff5)),
                      right: BorderSide(width: 5, color: Color(0x9900f5d4)),
                      bottom: BorderSide(width: 5, color: Colors.transparent),
                      left: BorderSide(width: 5, color: Colors.transparent),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

// ignore: unused_element
class _ShieldPainter extends CustomPainter {
  final double angle, power;
  const _ShieldPainter({required this.angle, required this.power});
  @override
  void paint(Canvas c, Size s) {
    final o = s.center(Offset.zero), r = s.shortestSide * .49;
    c.drawCircle(
      o,
      r,
      Paint()
        ..color = Color.lerp(
          const Color(0xff161e2c),
          const Color(0xff143848),
          power,
        )!,
    );
    c.drawCircle(
      o,
      r * .94,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Color.lerp(
          const Color(0x5ac8e8ff),
          const Color(0xa8a8ffe8),
          power,
        )!,
    );
    for (var i = 0; i < 6; i++) {
      final a = angle * (.12 + power * .6) + i * math.pi / 3,
          p = o + Offset(math.cos(a), math.sin(a)) * r * .68;
      c.drawCircle(
        p,
        r * .075,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Color.lerp(
            const Color(0x447aa7aa),
            const Color(0xaa7ef5e0),
            power,
          )!,
      );
    }
    final p = Path()
      ..moveTo(o.dx, o.dy - r * .48)
      ..cubicTo(
        o.dx + r * .2,
        o.dy - r * .48,
        o.dx + r * .38,
        o.dy - r * .42,
        o.dx + r * .38,
        o.dy - r * .23,
      )
      ..lineTo(o.dx + r * .38, o.dy + r * .03)
      ..cubicTo(
        o.dx + r * .36,
        o.dy + r * .27,
        o.dx + r * .2,
        o.dy + r * .45,
        o.dx,
        o.dy + r * .56,
      )
      ..cubicTo(
        o.dx - r * .2,
        o.dy + r * .45,
        o.dx - r * .36,
        o.dy + r * .27,
        o.dx - r * .38,
        o.dy + r * .03,
      )
      ..lineTo(o.dx - r * .38, o.dy - r * .23)
      ..cubicTo(
        o.dx - r * .38,
        o.dy - r * .42,
        o.dx - r * .2,
        o.dy - r * .48,
        o.dx,
        o.dy - r * .48,
      )
      ..close();
    final fill = Paint()..color = const Color(0xff0c141e);
    if (power > .02) {
      fill.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xfffafffe), Color(0xff7fe8d4), Color(0xff2f7aa8)],
      ).createShader(Rect.fromCircle(center: o, radius: r));
    }
    c.drawPath(p, fill);
    c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = Color.lerp(
          const Color(0x78b8e0ff),
          const Color(0xdcf5fcff),
          power,
        )!,
    );
    if (power > .1) {
      final face = Paint()..color = Color.fromRGBO(20, 35, 40, power);
      c.drawCircle(o + Offset(0, r * .05), r * .18, face);
      final eye = Paint()..color = Color.fromRGBO(255, 255, 255, power);
      c.drawCircle(o + Offset(-r * .07, r * .02), r * .025, eye);
      c.drawCircle(o + Offset(r * .07, r * .02), r * .025, eye);
      c.drawArc(
        Rect.fromCenter(
          center: o + Offset(0, r * .08),
          width: r * .2,
          height: r * .12,
        ),
        0,
        math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = eye.color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter o) =>
      o.angle != angle || o.power != power;
}

// ignore: unused_element
class _LaunchPainter extends CustomPainter {
  final double t;
  const _LaunchPainter(this.t);
  @override
  void paint(Canvas c, Size s) {
    if (t <= 0 || t >= 1) return;
    final o = s.center(Offset.zero), f = math.sin(t * math.pi);
    c.drawRect(
      Offset.zero & s,
      Paint()..color = Color.fromRGBO(5, 20, 28, .38 * f),
    );
    for (var i = 0; i < 3; i++) {
      final r = (40 + s.width * ((t + i * .14) % 1)) * .65;
      c.drawCircle(
        o,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t)
          ..color = Color.fromRGBO(126, 245, 224, f * (1 - i * .22)),
      );
    }
    c.drawCircle(
      o,
      18 + 90 * math.sin(t * math.pi),
      Paint()
        ..shader = RadialGradient(
          colors: [Color.fromRGBO(184, 255, 245, .8 * f), Colors.transparent],
        ).createShader(Rect.fromCircle(center: o, radius: 108)),
    );
  }

  @override
  bool shouldRepaint(covariant _LaunchPainter o) => o.t != t;
}
