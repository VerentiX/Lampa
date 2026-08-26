/// Resolves Хаттабыч `/auto/{subId}` URLs with primary / fallback / reserve hosts
/// (ported from old Lampa `SubscriptionUrlResolver`).
class SubscriptionUrlResolver {
  static const primaryHost = 'gw.zizmos.ru';
  static const fallbackHost = 'sub.subhotig.buzz';
  static const reserveHost = 'v.hattabych.ru';

  static final _subIdPath = RegExp(r'/auto/([A-Za-z0-9_-]{6,128})/?');

  static String? extractSubId(String? url) {
    final normalized = url?.trim() ?? '';
    if (normalized.isEmpty) return null;
    return _subIdPath.firstMatch(normalized)?.group(1);
  }

  static bool isManagedSubscriptionUrl(String? url) =>
      extractSubId(url) != null;

  /// Primary → fallback → reserve. Non-managed URLs return the original only.
  static List<String> candidateUrls(String originalUrl) {
    final trimmed = originalUrl.trim();
    final subId = extractSubId(trimmed);
    if (subId == null) return [trimmed];
    return [
      primaryHost,
      fallbackHost,
      reserveHost,
    ].map((h) => buildUrl(h, subId)).toSet().toList();
  }

  /// Always store the primary host so settings stay stable across fallbacks.
  static String normalizeStoredUrl(String url) {
    final subId = extractSubId(url);
    if (subId == null) return url.trim();
    return buildUrl(primaryHost, subId);
  }

  static String buildUrl(String host, String subId) =>
      'https://$host/auto/$subId';
}
