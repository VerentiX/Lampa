import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/builder/post_steps.dart';

void main() {
  group('healDanglingRouteFinal', () {
    test('repairs stale Lampa priority tag to vpn-1', () {
      final config = <String, dynamic>{
        'outbounds': [
          {'type': 'direct', 'tag': 'direct-out'},
          {
            'type': 'selector',
            'tag': 'vpn-1',
            'outbounds': ['direct-out'],
          },
        ],
        'route': {'final': 'priority-route-final'},
      };

      final warning = healDanglingRouteFinal(config);

      expect((config['route'] as Map)['final'], 'vpn-1');
      expect(warning, contains('priority-route-final'));
    });

    test('keeps an existing final untouched', () {
      final config = <String, dynamic>{
        'outbounds': [
          {'type': 'direct', 'tag': 'direct-out'},
        ],
        'route': {'final': 'direct-out'},
      };

      expect(healDanglingRouteFinal(config), isNull);
      expect((config['route'] as Map)['final'], 'direct-out');
    });

    test('falls back to direct when vpn-1 is unavailable', () {
      final config = <String, dynamic>{
        'outbounds': [
          {'type': 'direct', 'tag': 'direct-out'},
        ],
        'route': {'final': 'missing'},
      };

      healDanglingRouteFinal(config);

      expect((config['route'] as Map)['final'], 'direct-out');
    });
  });
}
