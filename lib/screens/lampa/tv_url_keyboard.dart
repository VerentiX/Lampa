import 'package:flutter/material.dart';

import '../../widgets/remote_button.dart';
import 'lampa_ui.dart';

/// Subscription URL entry for a television remote.
///
/// The system keyboard on these devices is a phone touch layout. Its keys are
/// not focusable, and a focused [TextField] consumes D-pad events as caret
/// movement, so the remote can never reach a key. This pad stays inside the
/// Flutter focus tree.
class TvSubscriptionEntry extends StatefulWidget {
  const TvSubscriptionEntry({super.key});

  @override
  State<TvSubscriptionEntry> createState() => _TvSubscriptionEntryState();
}

enum _PadPage { lower, upper, symbols }

class _TvSubscriptionEntryState extends State<TvSubscriptionEntry> {
  static const _lower = <String>[
    '1234567890',
    'qwertyuiop',
    'asdfghjkl-',
    'zxcvbnm._/',
  ];
  static const _upper = <String>[
    '1234567890',
    'QWERTYUIOP',
    'ASDFGHJKL-',
    'ZXCVBNM._/',
  ];
  static const _symbols = <List<String>>[
    [':', '/', '?', '#', '@', '&', '=', '%', '+', '~'],
    ['!', r'$', '(', ')', '*', ',', ';', '[', ']', '\\'],
    ['{', '}', '|', '^', '`', '<', '>', "'", '"', '_'],
  ];

  var _text = '';
  var _page = _PadPage.lower;
  var _focusFirst = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusFirst = false;
    });
  }

  List<List<String>> get _rows {
    switch (_page) {
      case _PadPage.lower:
        return [for (final row in _lower) row.split('')];
      case _PadPage.upper:
        return [for (final row in _upper) row.split('')];
      case _PadPage.symbols:
        return _symbols;
    }
  }

  void _type(String char) => setState(() => _text += char);

  void _backspace() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.substring(0, _text.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: LampaUi.border)),
            child: SingleChildScrollView(
              child: Text(
                _text.isEmpty ? 'Вставьте ссылку подписки Хаттабыч' : _text,
                key: const ValueKey('tv-url-preview'),
                style: LampaUi.mono.copyWith(
                  color: _text.isEmpty ? LampaUi.muted : LampaUi.onSurface,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var rowIndex = 0; rowIndex < _rows.length; rowIndex++)
            Row(
              children: [
                for (final char in _rows[rowIndex])
                  Expanded(
                    child: _key(
                      char,
                      autofocus:
                          _focusFirst &&
                          _page == _PadPage.lower &&
                          rowIndex == 0 &&
                          char == '1',
                      onPressed: () => _type(char),
                    ),
                  ),
              ],
            ),
          Row(
            children: [
              Expanded(child: _key('Стереть', onPressed: _backspace)),
              Expanded(
                child: _key(
                  _page == _PadPage.upper ? 'abc' : 'ABC',
                  buttonKey: const ValueKey('tv-shift'),
                  onPressed: () => setState(() {
                    _page = _page == _PadPage.upper
                        ? _PadPage.lower
                        : _PadPage.upper;
                  }),
                ),
              ),
              Expanded(
                child: _key(
                  _page == _PadPage.symbols ? 'abc' : ':/?',
                  buttonKey: const ValueKey('tv-symbols'),
                  onPressed: () => setState(() {
                    _page = _page == _PadPage.symbols
                        ? _PadPage.lower
                        : _PadPage.symbols;
                  }),
                ),
              ),
              Expanded(
                child: _key(
                  'Очистить',
                  onPressed: () => setState(() => _text = ''),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _key('Отмена', onPressed: () => Navigator.pop(context)),
              ),
              Expanded(
                flex: 2,
                child: _key(
                  'Добавить',
                  color: LampaUi.accent,
                  onPressed: () => Navigator.pop(context, _text.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _key(
    String label, {
    Key? buttonKey,
    bool autofocus = false,
    Color? color,
    required VoidCallback onPressed,
  }) {
    return RemoteButton(
      key: buttonKey ?? ValueKey('tv-key-$label'),
      autofocus: autofocus,
      onPressed: onPressed,
      label: label,
      child: SizedBox(
        height: 32,
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: color ?? LampaUi.onSurface,
              fontSize: label.length > 1 ? 13 : 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
