import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/settings_storage.dart';
import 'lampa_ui.dart';

class LampaUpdateSettingsScreen extends StatefulWidget {
  const LampaUpdateSettingsScreen({super.key});

  @override
  State<LampaUpdateSettingsScreen> createState() =>
      _LampaUpdateSettingsScreenState();
}

class _LampaUpdateSettingsScreenState extends State<LampaUpdateSettingsScreen> {
  static const _ceremony = MethodChannel('com.leadaxe.lxbox/lampa_ceremony');

  int _sub = 12;
  int _app = 24;
  int _geo = 24;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_ceremony.invokeMethod<void>('hide'));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_ceremony.invokeMethod<void>('show'));
    super.dispose();
  }

  Future<void> _load() async {
    final sub = await SettingsStorage.getLampaSubUpdateHours();
    final app = await SettingsStorage.getLampaAppCheckHours();
    final geo = await SettingsStorage.getLampaGeoCheckHours();
    if (!mounted) return;
    setState(() {
      _sub = sub;
      _app = app;
      _geo = geo;
      _loaded = true;
    });
  }

  Future<void> _setSub(int hours) async {
    setState(() => _sub = hours);
    await SettingsStorage.setLampaSubUpdateHours(hours);
  }

  Future<void> _setApp(int hours) async {
    setState(() => _app = hours);
    await SettingsStorage.setLampaAppCheckHours(hours);
  }

  Future<void> _setGeo(int hours) async {
    setState(() => _geo = hours);
    await SettingsStorage.setLampaGeoCheckHours(hours);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LampaUi.bgDeep,
      appBar: AppBar(
        backgroundColor: LampaUi.bgDeep,
        elevation: 0,
        title: const Text('Автообновление'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Text(
                  'Если есть обновление, приложение и геофайлы скачиваются сами — '
                  'с докачкой после разрыва сети. Ручная проверка по-прежнему '
                  'спрашивает перед загрузкой.',
                  style: TextStyle(color: LampaUi.muted, height: 1.35),
                ),
                const SizedBox(height: 18),
                _IntervalCard(
                  title: 'Подписка',
                  subtitle: 'Как часто подтягивать список серверов',
                  value: _sub,
                  onChanged: _setSub,
                ),
                const SizedBox(height: 12),
                _IntervalCard(
                  title: 'Приложение',
                  subtitle: 'Проверка новой версии Lampa',
                  value: _app,
                  onChanged: _setApp,
                ),
                const SizedBox(height: 12),
                _IntervalCard(
                  title: 'Геофайлы',
                  subtitle: 'Базы маршрутизации (GeoIP / GeoSite)',
                  value: _geo,
                  onChanged: _setGeo,
                ),
              ],
            ),
    );
  }
}

class _IntervalCard extends StatelessWidget {
  const _IntervalCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final int value;
  final Future<void> Function(int hours) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xff14100c),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x44c4a574)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: LampaUi.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Text(
              subtitle,
              style: const TextStyle(color: LampaUi.muted, fontSize: 13),
            ),
          ),
          for (final h in SettingsStorage.lampaIntervalChoicesHours)
            RadioListTile<int>(
              value: h,
              groupValue: value,
              onChanged: (v) {
                if (v != null) unawaited(onChanged(v));
              },
              activeColor: LampaUi.accentDeep,
              title: Text(
                _label(h),
                style: const TextStyle(color: LampaUi.onSurface),
              ),
              dense: true,
            ),
        ],
      ),
    );
  }

  static String _label(int hours) {
    if (hours <= 0) return 'Только вручную';
    if (hours == 1) return 'Каждый час';
    if (hours == 24) return 'Раз в сутки';
    if (hours == 48) return 'Раз в 2 дня';
    if (hours == 168) return 'Раз в неделю';
    return 'Каждые $hours ч';
  }
}
