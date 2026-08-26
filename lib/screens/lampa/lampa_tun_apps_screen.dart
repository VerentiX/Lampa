import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/home_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/app_info.dart';
import '../../services/app_info_cache.dart';
import '../../services/settings_storage.dart';

/// Full installed-apps checklist (old Lampa style): check = bypass/through VPN.
/// Pops `true` if settings changed (caller restarts tunnel only then).
class LampaTunAppsScreen extends StatefulWidget {
  const LampaTunAppsScreen({
    super.key,
    required this.homeController,
    required this.subController,
  });

  final HomeController homeController;
  final SubscriptionController subController;

  @override
  State<LampaTunAppsScreen> createState() => _LampaTunAppsScreenState();
}

class _LampaTunAppsScreenState extends State<LampaTunAppsScreen> {
  static const _ceremony = MethodChannel('com.leadaxe.lxbox/lampa_ceremony');

  TunAppsConfig _initial =
      const TunAppsConfig(mode: 'deny', packages: <String>[]);
  String _mode = 'deny';
  final Set<String> _selected = {};
  List<AppInfo> _apps = [];
  bool _loading = true;
  bool _showSystem = false;
  String _search = '';
  bool _popping = false;

  @override
  void initState() {
    super.initState();
    unawaited(_ceremony.invokeMethod<void>('hide'));
    _load();
  }

  @override
  void dispose() {
    unawaited(_ceremony.invokeMethod<void>('show'));
    super.dispose();
  }

  Future<void> _load() async {
    var cfg = await SettingsStorage.getTunApps();
    if (cfg.mode == 'off' && cfg.packages.isEmpty) {
      cfg = const TunAppsConfig(mode: 'deny', packages: <String>[]);
    }
    final apps = await AppInfoCache.loadAllApps();
    if (!mounted) return;
    setState(() {
      _initial = cfg;
      _mode = (cfg.mode == 'off') ? 'deny' : cfg.mode;
      _selected
        ..clear()
        ..addAll(cfg.packages);
      _apps = apps;
      _loading = false;
    });
  }

  Future<void> _reloadApps() async {
    final apps = await AppInfoCache.loadAllApps(force: true);
    if (!mounted) return;
    setState(() => _apps = apps);
  }

  bool get _dirty {
    final pkgs = _selected.toList()..sort();
    final initPkgs = List<String>.from(_initial.packages)..sort();
    final initMode = (_initial.mode == 'off' && _initial.packages.isEmpty)
        ? 'deny'
        : _initial.mode;
    if (_mode != initMode) return true;
    if (pkgs.length != initPkgs.length) return true;
    for (var i = 0; i < pkgs.length; i++) {
      if (pkgs[i] != initPkgs[i]) return true;
    }
    return false;
  }

  List<AppInfo> get _filtered {
    var list = _apps.where((a) => _showSystem || !a.isSystem).toList();
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where(
            (a) =>
                a.appName.toLowerCase().contains(q) ||
                a.packageName.toLowerCase().contains(q),
          )
          .toList();
    }
    list.sort((a, b) {
      final sa = _selected.contains(a.packageName) ? 0 : 1;
      final sb = _selected.contains(b.packageName) ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
      return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
    });
    return list;
  }

  Future<void> _pop() async {
    if (_popping) return;
    _popping = true;
    final changed = _dirty;
    if (changed) {
      await SettingsStorage.setTunApps(
        TunAppsConfig(mode: _mode, packages: _selected.toList()),
      );
      widget.subController.configDirty = true;
    }
    if (!mounted) return;
    Navigator.pop(context, changed);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xff0a0603),
        appBar: AppBar(
          backgroundColor: const Color(0xff140e08),
          title: const Text('Раздельное туннелирование'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _pop,
          ),
          actions: [
            IconButton(
              tooltip: 'Обновить список',
              onPressed: _loading ? null : _reloadApps,
              icon: const Icon(Icons.sync),
            ),
            IconButton(
              tooltip: _showSystem ? 'Скрыть системные' : 'Показать системные',
              onPressed: () => setState(() => _showSystem = !_showSystem),
              icon: Icon(
                _showSystem ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(
                      children: [
                        _modeTile(
                          mode: 'deny',
                          title: 'Приложения в обход VPN',
                          subtitle:
                              'Галочка = приложение идёт мимо VPN. Остальные — через VPN.',
                        ),
                        _modeTile(
                          mode: 'allow',
                          title: 'Приложения через VPN',
                          subtitle:
                              'Галочка = только это приложение через VPN. Остальные — напрямую.',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Поиск приложения',
                        hintStyle: const TextStyle(color: Color(0x66ffffff)),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0x99ffffff),
                        ),
                        filled: true,
                        fillColor: const Color(0x14ffffff),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setState(() => _search = v.trim()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Отмечено: ${_selected.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0x99ffffff),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final app = _filtered[i];
                        final checked = _selected.contains(app.packageName);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selected.add(app.packageName);
                              } else {
                                _selected.remove(app.packageName);
                              }
                            });
                          },
                          secondary: _icon(app),
                          title: Text(
                            app.appName,
                            style: const TextStyle(fontSize: 15),
                          ),
                          subtitle: Text(
                            app.packageName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0x66ffffff),
                            ),
                          ),
                          activeColor: const Color(0xffff8f00),
                          checkColor: const Color(0xff1a1008),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _modeTile({
    required String mode,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0x28ff8f00) : const Color(0x14ffffff),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _mode = mode),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? const Color(0xffffc46b)
                      : const Color(0x66ffffff),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? const Color(0xffffe0a8)
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0x99ffffff),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon(AppInfo app) {
    AppInfoCache.ensure(app.packageName);
    final info = AppInfoCache.of(app.packageName) ?? app;
    if (info.icon != null) {
      return Image.memory(info.icon!, width: 36, height: 36);
    }
    final letter = app.appName.isNotEmpty
        ? app.appName.characters.first.toUpperCase()
        : '?';
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0x33ffffff),
      child: Text(letter, style: const TextStyle(fontSize: 14)),
    );
  }
}
