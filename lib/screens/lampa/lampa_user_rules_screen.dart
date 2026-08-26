import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/lampa_user_rules.dart';
import 'lampa_ui.dart';

/// Domain lists that sit above split-tunnel / roscom routing.
class LampaUserRulesScreen extends StatefulWidget {
  const LampaUserRulesScreen({super.key});

  @override
  State<LampaUserRulesScreen> createState() => _LampaUserRulesScreenState();
}

class _LampaUserRulesScreenState extends State<LampaUserRulesScreen> {
  static const _ceremony = MethodChannel('com.leadaxe.lxbox/lampa_ceremony');

  LampaUserRules _saved = const LampaUserRules();
  final List<String> _vpn = [];
  final List<String> _direct = [];
  final _vpnCtrl = TextEditingController();
  final _directCtrl = TextEditingController();
  bool _loaded = false;

  bool get _dirty {
    if (_vpn.length != _saved.throughVpn.length) return true;
    if (_direct.length != _saved.bypassVpn.length) return true;
    for (var i = 0; i < _vpn.length; i++) {
      if (_vpn[i] != _saved.throughVpn[i]) return true;
    }
    for (var i = 0; i < _direct.length; i++) {
      if (_direct[i] != _saved.bypassVpn[i]) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_ceremony.invokeMethod<void>('hide'));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_ceremony.invokeMethod<void>('show'));
    _vpnCtrl.dispose();
    _directCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rules = await LampaUserRules.load();
    if (!mounted) return;
    setState(() {
      _saved = rules;
      _vpn
        ..clear()
        ..addAll(rules.throughVpn);
      _direct
        ..clear()
        ..addAll(rules.bypassVpn);
      _loaded = true;
    });
  }

  void _add(bool vpn) {
    final ctrl = vpn ? _vpnCtrl : _directCtrl;
    final n = LampaUserRules.normalizeDomain(ctrl.text);
    if (n == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        LampaUi.snack('Введите домен, например example.com'),
      );
      return;
    }
    setState(() {
      if (vpn) {
        _direct.remove(n);
        if (!_vpn.contains(n)) _vpn.add(n);
      } else {
        _vpn.remove(n);
        if (!_direct.contains(n)) _direct.add(n);
      }
      ctrl.clear();
    });
  }

  Future<void> _save() async {
    final next = LampaUserRules(
      throughVpn: List.of(_vpn),
      bypassVpn: List.of(_direct),
    );
    await next.save();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LampaUi.bgDeep,
      appBar: AppBar(
        backgroundColor: LampaUi.bgDeep,
        elevation: 0,
        title: const Text('Мои правила'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _DomainCard(
                  title: 'Через VPN',
                  count: _vpn.length,
                  controller: _vpnCtrl,
                  domains: _vpn,
                  emptyText: 'Пока пусто — сайт пойдёт по общим правилам',
                  onAdd: () => _add(true),
                  onRemove: (d) => setState(() => _vpn.remove(d)),
                  onClear: _vpn.isEmpty
                      ? null
                      : () => setState(() => _vpn.clear()),
                ),
                const SizedBox(height: 16),
                _DomainCard(
                  title: 'Мимо VPN',
                  count: _direct.length,
                  controller: _directCtrl,
                  domains: _direct,
                  emptyText: 'Пока пусто — сайт пойдёт напрямую',
                  onAdd: () => _add(false),
                  onRemove: (d) => setState(() => _direct.remove(d)),
                  onClear: _direct.isEmpty
                      ? null
                      : () => setState(() => _direct.clear()),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _dirty ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: LampaUi.accentDeep,
                foregroundColor: Colors.black,
                disabledBackgroundColor: const Color(0xff5c5c5c),
                disabledForegroundColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Сохранить',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DomainCard extends StatelessWidget {
  const _DomainCard({
    required this.title,
    required this.count,
    required this.controller,
    required this.domains,
    required this.emptyText,
    required this.onAdd,
    required this.onRemove,
    required this.onClear,
  });

  final String title;
  final int count;
  final TextEditingController controller;
  final List<String> domains;
  final String emptyText;
  final VoidCallback onAdd;
  final void Function(String domain) onRemove;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xff14100c),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x44c4a574)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: LampaUi.onSurface,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0x99ffffff),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(color: LampaUi.onSurface),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAdd(),
                  decoration: InputDecoration(
                    prefixText: 'https://',
                    prefixStyle: const TextStyle(
                      color: Color(0x88ffffff),
                      fontSize: 16,
                    ),
                    hintText: 'example.com',
                    hintStyle: const TextStyle(color: Color(0x55ffffff)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0x66c4a574)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: LampaUi.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: LampaUi.accentDeep,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: onAdd,
                  borderRadius: BorderRadius.circular(10),
                  child: const SizedBox(
                    width: 46,
                    height: 46,
                    child: Icon(Icons.add, color: Colors.black, size: 28),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (domains.isEmpty)
            Text(
              emptyText,
              style: const TextStyle(color: Color(0x66ffffff), fontSize: 13),
            )
          else
            for (final d in domains)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xff2a241c),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          d,
                          style: const TextStyle(
                            color: LampaUi.onSurface,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => onRemove(d),
                        icon: const Icon(Icons.close, color: Color(0xffe53935)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
          if (onClear != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onClear,
                child: const Text(
                  'Очистить все',
                  style: TextStyle(color: Color(0xffe53935)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
