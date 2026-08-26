import 'package:flutter/services.dart';

class LegacyLampaMigration {
  static const _channel = MethodChannel('com.leadaxe.lxbox/utils');
  static Future<List<String>> subscriptionUrls() async {
    try {
      final rows = await _channel.invokeListMethod<dynamic>(
        'legacyLampaSubscriptions',
      );
      if (rows == null) return const [];
      return rows
          .whereType<Map>()
          .map((e) => '${e['url'] ?? ''}'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
