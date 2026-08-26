import 'package:flutter_test/flutter_test.dart';
import 'package:lxbox/services/priority_routing.dart';
import 'package:lxbox/vpn/cc_channel.dart';

CcGroup group(String tag, String selected) => CcGroup(
  tag: tag,
  type: 'Selector',
  selectable: true,
  selected: selected,
  isExpand: false,
  items: const [],
);

CcGroup urltestGroup(String tag, String selected, int delay) => CcGroup(
  tag: tag,
  type: 'URLTest',
  selectable: false,
  selected: selected,
  isExpand: false,
  items: [
    CcOutbound(
      tag: selected,
      type: 'vless',
      urlTestDelay: delay,
      urlTestTime: delay >= 0 ? 1 : 0,
    ),
  ],
);

void main() {
  test('priority parser accepts real subscription tags', () {
    expect(priorityFromTag('P15-Riga-Обход-TimeWeb'), 15);
    expect(priorityFromTag('node-p5+'), 5);
    expect(priorityFromTag('p4-amsterdam'), 4);
    expect(priorityFromTag('server15'), isNull);
  });

  test('follows selector to urltest leaf and enables p5+', () {
    final decision = priorityRoutingDecision([
      group('vpn-1', 'vpn-1-auto'),
      urltestGroup('vpn-1-auto', 'P15-Riga', 42),
    ], 'vpn-1');
    expect(decision?.nodeTag, 'P15-Riga');
    expect(decision?.proxyOutbound, 'vpn-1');
    expect(decision?.p5Plus, isTrue);
  });

  test('dead p5 urltest selection falls back to default routing tier', () {
    final decision = priorityRoutingDecision([
      group('vpn-1', 'vpn-1-auto'),
      urltestGroup('vpn-1-auto', 'P15-Riga', -1),
    ], 'vpn-1');
    expect(decision?.nodeTag, 'P15-Riga');
    expect(decision?.p5Plus, isFalse);
  });

  test('p0-p4 leaf selects default tier', () {
    final decision = priorityRoutingDecision([
      group('vpn-1', 'P4-Moscow'),
    ], 'vpn-1');
    expect(decision?.p5Plus, isFalse);
  });

  test('incomplete snapshot and cycles do not change routing', () {
    expect(priorityRoutingDecision([group('vpn-1', '')], 'vpn-1'), isNull);
    expect(
      priorityRoutingDecision([
        group('vpn-1', 'auto'),
        group('auto', 'vpn-1'),
      ], 'vpn-1'),
      isNull,
    );
  });
}
