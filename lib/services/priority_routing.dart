import '../vpn/cc_channel.dart';

/// Dynamic RoscomVPN routing tier derived from the leaf selected by a
/// selector/urltest chain.
class PriorityRoutingDecision {
  const PriorityRoutingDecision({
    required this.nodeTag,
    required this.proxyOutbound,
    required this.p5Plus,
  });

  final String nodeTag;
  final String proxyOutbound;
  final bool p5Plus;

  @override
  bool operator ==(Object other) =>
      other is PriorityRoutingDecision &&
      other.nodeTag == nodeTag &&
      other.proxyOutbound == proxyOutbound &&
      other.p5Plus == p5Plus;

  @override
  int get hashCode => Object.hash(nodeTag, proxyOutbound, p5Plus);
}

int? priorityFromTag(String tag) {
  final match = RegExp(
    r'(?:^|[^a-z0-9])p(\d+)(?=[^0-9]|$)',
    caseSensitive: false,
  ).firstMatch(tag);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Follows group selections until the concrete outbound is reached.
/// Cycles and incomplete urltest snapshots intentionally return null: changing
/// routing on uncertain state is worse than keeping the last stable profile.
PriorityRoutingDecision? priorityRoutingDecision(
  List<CcGroup> groups,
  String? rootGroup,
) {
  if (rootGroup == null || rootGroup.isEmpty) return null;
  final selected = <String, String>{
    for (final group in groups)
      if (group.selected.isNotEmpty) group.tag: group.selected,
  };
  final byTag = <String, CcGroup>{for (final group in groups) group.tag: group};

  final seen = <String>{};
  var current = rootGroup;
  for (var depth = 0; depth < 16; depth++) {
    if (!seen.add(current)) return null;
    final next = selected[current];
    if (next == null || next.isEmpty) {
      // A root absent from the group map is not a valid selector snapshot.
      if (current == rootGroup) return null;
      final priority = priorityFromTag(current);
      if (priority == null) return null;
      return PriorityRoutingDecision(
        nodeTag: current,
        proxyOutbound: rootGroup,
        p5Plus: priority >= 5,
      );
    }
    final currentGroup = byTag[current];
    if (currentGroup != null &&
        currentGroup.type.toLowerCase().contains('urltest')) {
      CcOutbound? selectedItem;
      for (final item in currentGroup.items) {
        if (item.tag == next) {
          selectedItem = item;
          break;
        }
      }
      // A stale URLTest selection is not proof that its priority route is
      // usable. Fail closed to the default routing tier until the core has a
      // fresh successful probe for the selected leaf.
      if (selectedItem == null || selectedItem.urlTestTime <= 0) {
        return PriorityRoutingDecision(
          nodeTag: next,
          proxyOutbound: rootGroup,
          p5Plus: false,
        );
      }
    }
    current = next;
  }
  return null;
}
