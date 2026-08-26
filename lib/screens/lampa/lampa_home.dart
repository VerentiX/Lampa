import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/home_state.dart';
import '../../models/node_spec.dart';
import '../../models/tunnel_status.dart';
import '../../services/format_utils.dart' as fmt;
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

  static String _subsSig(List<SubscriptionEntry> subs) => subs
      .map((e) => '${e.id}|${e.enabled}|${e.url}|${e.nodeCount}')
      .join(';');

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
    for (final candidate in [
      metaTitle,
      e.name.trim(),
      e.displayName.trim(),
    ]) {
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
        final full = e.tagPrefix.isEmpty
            ? n.tag
            : '${e.tagPrefix} ${n.tag}';
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
      future.then((info) {
        if (!mounted || _subId != id) return;
        setState(() => _billingTitle = info.title);
      }).catchError((_) {});
    }
    if (scheduleRebuild && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final up = widget.state.tunnelUp;
    return Scaffold(
      backgroundColor: const Color(0xff0a0603),
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
                        icon: const Icon(Icons.more_vert),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Добавить подписку',
                        onPressed: _showImportMenu,
                        icon: const Icon(Icons.add),
                      ),
                      IconButton(
                        tooltip: 'Импорт из буфера',
                        onPressed: _importClipboard,
                        icon: const Icon(Icons.content_paste),
                      ),
                      const _LampaDownloadBadge(),
                      Padding(
                        padding: const EdgeInsets.only(right: 10, left: 2),
                        child: Text(
                          VersionInfo.I.version,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0x88ffffff),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Column(
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -10),
                        child: _PowerDock(
                          connecting:
                              widget.state.tunnel == TunnelStatus.connecting,
                          // Keep "on" look while Stopping — avoids a heavy
                          // disconnect flip fighting VPN teardown on the UI thread.
                          connected: up ||
                              widget.state.tunnel == TunnelStatus.stopping,
                          onTap: _working ? null : widget.onToggle,
                        ),
                      ),
                      Text(
                        _profileTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (widget.onOpenSplitTunnel != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
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
                                        const Text(
                                          'Раздельное туннелирование',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Color(0xe6ffffff),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _splitSummary,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0x99ffffff),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0x66ffffff),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (widget.onOpenUserRules != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
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
                                        const Text(
                                          'Мои правила',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Color(0xe6ffffff),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _rulesSummary,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0x99ffffff),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0x66ffffff),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Material(
                        color: const Color(0x22ff8f00),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: _working ? null : _refreshSubscription,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.refresh,
                                  color: Color(0xffffc46b),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Обновить подписку',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xffffe0a8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Connection check temporarily hidden.
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _pullRefresh,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Подписки',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (_urlSubs.length > 1)
                                const Text(
                                  'Выберите подписку',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0x80ffffff),
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
      content: SelectableText(url, style: const TextStyle(color: LampaUi.onSurface)),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) Navigator.pop(context);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                LampaUi.snack('Ссылка скопирована'),
              );
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
        ScaffoldMessenger.of(context).showSnackBar(
          LampaUi.snack('Обновлений нет'),
        );
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
    LampaDownloadProgress.I.start(
      kind: LampaDownloadKind.app,
      label: 'Приложение ${info.version}',
    );
    final messenger = ScaffoldMessenger.of(context);
    final apk = await LampaAppUpdate.I.download(
      info,
      onProgress: (got, total) {
        LampaDownloadProgress.I.update(
          kind: LampaDownloadKind.app,
          received: got,
          total: total,
        );
      },
    );
    LampaDownloadProgress.I.finish(LampaDownloadKind.app);
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
        ScaffoldMessenger.of(context).showSnackBar(
          LampaUi.snack('В буфере обмена нет ссылки подписки'),
        );
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
    final resolve = await SettingsStorage.getVar('resolve_enabled', 'true');
    var asIs = resolve != 'true';
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
                        'Стратегия резолва',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0x99ffffff),
                        ),
                      ),
                    ),
                    RadioListTile<bool>(
                      value: true,
                      groupValue: asIs,
                      activeColor: const Color(0xffff8f00),
                      title: const Text('AsIs'),
                      subtitle: const Text('Облегчённая — только домен, без резолва IP.'),
                      onChanged: (v) => setSheet(() => asIs = v!),
                    ),
                    RadioListTile<bool>(
                      value: false,
                      groupValue: asIs,
                      activeColor: const Color(0xffff8f00),
                      title: const Text('IPIfNonMatch'),
                      subtitle: const Text(
                        'Усиленная — если домен не совпал, резолв IP.',
                      ),
                      onChanged: (v) => setSheet(() => asIs = v!),
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
    await SettingsStorage.setVar(
      'resolve_enabled',
      asIs ? 'false' : 'true',
    );
    await widget.onNetworkSettingsChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      LampaUi.snack('Настройки сети сохранены'),
    );
  }

  Future<void> _refreshSubscription() async {
    await widget.onRefreshSubscription();
    await _syncConnectionRemark();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      LampaUi.snack('Подписка обновлена'),
    );
    if (_subId == null) return;
    final future = _billing.subscription(_subId!);
    setState(() => _info = future);
    try {
      final info = await future;
      if (mounted) setState(() => _billingTitle = info.title);
    } catch (_) {}
  }

  Widget _chip(IconData icon) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: const Color(0x1a00f5d4),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0x4400f5d4)),
    ),
    child: Icon(icon, size: 20, color: const Color(0xff00f5d4)),
  );

  Widget _subscriptionCard() {
    final subs = _urlSubs;
    if (subs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0x1fffffff),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0x33ffffff)),
        ),
        child: const Text(
          'Подписок пока нет. Добавьте ссылку сверху.',
          style: TextStyle(color: Color(0x99ffffff)),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < subs.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _oneSubscriptionCard(subs[i]),
        ],
      ],
    );
  }

  Widget _oneSubscriptionCard(SubscriptionEntry entry) {
    final multi = _urlSubs.length > 1;
    final active = identical(entry, _activeSub) ||
        (entry.enabled && entry.id == _activeSub?.id);
    final title = _connectionName(entry);
    final shown = title.isNotEmpty ? title : 'Хаттабыч VPN';
    final nodes = entry.nodeCount;
    final expandedId = _expandedSubId ?? (active ? entry.id : null);
    final expanded = expandedId == entry.id;
    // Soft Hottabych (warm lamp / amber) — only when several subscriptions.
    final highlight = multi && active;
    final accent = highlight
        ? const Color(0x66ffb347)
        : const Color(0x33ffffff);
    final bg = highlight
        ? const Color(0x18ff8f00)
        : const Color(0x1fffffff);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent, width: highlight ? 1.2 : 1),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: () async {
              if (!active && widget.onSelectSubscription != null) {
                await widget.onSelectSubscription!(entry);
              }
              setState(() {
                _expandedSubId =
                    expanded && active ? null : entry.id;
              });
              _reload();
            },
            child: SizedBox(
              height: 72,
              child: Row(
                children: [
                  SizedBox(
                    width: 54,
                    child: AnimatedRotation(
                      turns: expanded ? 0 : -.25,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        Icons.arrow_drop_down,
                        size: 36,
                        color: highlight
                            ? const Color(0xffffc46b)
                            : const Color(0xc9ffffff),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                shown,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: highlight
                                      ? const Color(0xffffe7c2)
                                      : Colors.white,
                                ),
                              ),
                            ),
                            if (highlight) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x22ff8f00),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0x44ffb347),
                                  ),
                                ),
                                child: const Text(
                                  'Активна',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xffffc46b),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          nodes > 0
                              ? '$nodes конфигураций'
                              : 'Нажмите, чтобы выбрать',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0x8fffffff),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Действия',
                    color: const Color(0xff1a1208),
                    icon: const Icon(
                      Icons.more_vert,
                      color: Color(0xffd7f0ff),
                    ),
                    onSelected: (action) =>
                        _onSubMenuAction(action, entry),
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
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: expanded && active
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
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
        ScaffoldMessenger.of(context).showSnackBar(
          LampaUi.snack('Ссылка скопирована'),
        );
      case 'refresh':
        if (widget.onRefreshOne != null) {
          await widget.onRefreshOne!(entry);
        } else {
          await widget.onRefreshSubscription();
          await _syncConnectionRemark();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          LampaUi.snack('Подписка обновлена'),
        );
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
                    future.then((info) {
                      if (mounted) setState(() => _billingTitle = info.title);
                    }).catchError((_) {});
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
        return _statsBox(
          Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 24,
                    color: Color(0xff9ec4ff),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Container(
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0x30101635),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0x307aa7ff)),
                      ),
                      child: Text(
                        info.title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    info.daysLeft > 0
                        ? 'Осталось ${info.daysLeft} дн.'
                        : 'Срок истёк',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
              if (used > 0 || limit > 0) ...[
                const SizedBox(height: 10),
                _trafficRow(used: used, limit: limit),
              ],
              const SizedBox(height: 10),
              if (info.packages.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Пакеты',
                    style: TextStyle(fontSize: 12, color: Color(0x99ffffff)),
                  ),
                ),
                const SizedBox(height: 4),
                ...info.packages.map(_packageRow),
              ],
              if (info.paymentsEnabled && info.plans.isNotEmpty)
                TextButton(
                  onPressed: () => _choosePlan(info),
                  child: const SizedBox(
                    width: double.infinity,
                    child: Text(
                      'Продлить',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xffffd180)),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _trafficRow({required int used, required int limit}) {
    final pct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final usedLabel = fmt.formatBytes(used, spaced: true);
    final limitLabel =
        limit > 0 ? fmt.formatBytes(limit, spaced: true) : '∞';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: limit > 0 ? pct : null,
            minHeight: 6,
            backgroundColor: const Color(0x33101635),
            color: const Color(0xff00f5d4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Трафик: $usedLabel / $limitLabel',
          style: const TextStyle(fontSize: 11, color: Color(0x99ffffff)),
        ),
      ],
    );
  }

  Widget _packageRow(LampaOwnedPackage package) {
    final starts = package.startsAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(package.startsAt * 1000)
        : null;
    final startText = starts == null
        ? ''
        : '${starts.day.toString().padLeft(2, '0')}.${starts.month.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: package.active
                  ? const Color(0xff00f5d4)
                  : const Color(0xffffa726),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              package.active
                  ? '${package.title} — ещё ${package.daysLeft} дн.'
                  : '${package.title}${startText.isEmpty ? '' : ' — с $startText'} · ${package.daysLeft} дн.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (package.active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x3300f5d4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('сейчас', style: TextStyle(fontSize: 10)),
            ),
        ],
      ),
    );
  }

  Widget _statsBox(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0x24101635),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0x307aa7ff)),
    ),
    child: child,
  );
  Future<void> _choosePlan(LampaSubscriptionInfo info) async {
    final plan = await showModalBottomSheet<LampaPlan>(
      context: context,
      backgroundColor: const Color(0xff1a1208),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Выберите тариф',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...info.plans.map(
              (p) => ListTile(
                title: Text(p.title),
                subtitle: Text('${p.trafficGb} ГБ · ${p.days} дн.'),
                trailing: Text('${p.priceRub} ₽'),
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
      backgroundColor: const Color(0xff1a1208),
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
                onTap: () => Navigator.pop(context, (method: 'sbp', test: false)),
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
        ))
            .toString(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          LampaUi.snack('Ошибка оплаты: $e'),
        );
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
    constraints: const BoxConstraints(minHeight: 56),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0x22ffffff), Color(0x14ffffff)],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0x35ffffff)),
    ),
    child: child,
  );
}

class _CosmicBackground extends StatelessWidget {
  const _CosmicBackground();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [Color(0xff120a04), Color(0xff1e1208), Color(0xff0a0603)],
      ),
    ),
    child: CustomPaint(painter: _GlowPainter()),
  );
}

class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p1 = Offset(s.width * .5, s.height * .22),
        p2 = Offset(s.width * .82, s.height * .78);
    c.drawCircle(
      p1,
      s.width * 1.05,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x44ffab40), Color(0x00ffab40)],
        ).createShader(Rect.fromCircle(center: p1, radius: s.width * 1.05)),
    );
    c.drawCircle(
      p2,
      s.width * .9,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x33e64a19), Color(0x00e64a19)],
        ).createShader(Rect.fromCircle(center: p2, radius: s.width * .9)),
    );
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
        width: 220,
        height: 220,
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
