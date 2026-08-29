part of '../post_steps.dart';

/// Repairs a stale dynamic `route.final` after every outbound has been built.
///
/// Lampa changes this value at runtime for P0-P4/P5+ routing.  Older builds
/// could persist the conceptual tag `priority-route-final`, which is not a
/// real sing-box outbound and therefore made the whole config fail validation.
String? healDanglingRouteFinal(Map<String, dynamic> config) {
  final route = config['route'];
  if (route is! Map<String, dynamic>) return null;

  final current = route['final'];
  if (current is! String || current.isEmpty) return null;

  final tags = <String>{
    for (final item in (config['outbounds'] as List<dynamic>? ?? const []))
      if (item is Map<String, dynamic> && item['tag'] is String)
        item['tag'] as String,
    for (final item in (config['endpoints'] as List<dynamic>? ?? const []))
      if (item is Map<String, dynamic> && item['tag'] is String)
        item['tag'] as String,
  };
  if (tags.contains(current)) return null;

  final replacement = tags.contains('vpn-1')
      ? 'vpn-1'
      : tags.contains('direct-out')
      ? 'direct-out'
      : null;
  if (replacement == null) return null;

  route['final'] = replacement;
  return 'Route final "$current" does not exist — switched to "$replacement".';
}
