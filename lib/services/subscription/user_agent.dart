import '../version_info.dart';

/// User-Agent, отправляемый на каждый HTTP-fetch подписки.
///
/// **Зачем это важно.** Часть subscription-панелей (Remnawave / Marzban-типа)
/// маршрутизирует тело ответа по подстроке в User-Agent: клиента, опознанного
/// панелью, кормят base64/URI-списком, который парсер v2 умеет ингестить;
/// неопознанному клиенту панель может отдать полный sing-box JSON-конфиг
/// (`{dns,route,inbounds,outbounds,...}`) или generic-заглушку.
///
/// §368 — полный конфиг парсер теперь **разбирает** (узлы, группы, detour), так
/// что добавление подписки на нём больше не падает. UA всё равно оставляем
/// брендовым: base64/URI-list — более компактный и полный ответ панели, а из
/// конфига мы берём только транспортный слой.
///
/// Эмпирически (боевая панель `sub.vern13.ru`): UA с голым `singbox` (без
/// дефиса) → JSON-объект; UA с подстрокой `LxBox` → base64 URI-list. Поэтому
/// бренд-токена `LxBox-android` достаточно для распознавания — ни `sing-box`,
/// ни платформенный комментарий не нужны (см. таск 114).
///
/// Инварианты:
///   1. бренд-токен начинается с `LxBox-android/` — по нему панель опознаёт
///      клиента и отдаёт base64/URI-list; суффикс `-android` отличает от
///      десктопной сборки `LxBox-desktop`;
///   2. голой подстроки `singbox` (без дефиса) нет нигде — именно она триггерит
///      неправильную маршрутизацию (см. regression-тест в
///      `test/subscription/user_agent_test.dart`).
///
/// Формат:
///
/// ```
/// LxBox-android/<appVersion>
/// ```
///
/// например `LxBox-android/2.0.4`.

const _kProductToken = 'Lampa-Mobile-SB';

/// UA от старой Лампы / биллинга — для /auto/ даёт Xray-профиль, не sing-box.
bool isStaleLampaSubscriptionUa(String ua) {
  final t = ua.trim();
  if (t.isEmpty) return false;
  if (t == _kProductToken || t.startsWith('$_kProductToken/')) return false;
  if (t == 'Lampa-Subscription' || t.startsWith('Lampa-Subscription/')) {
    return true;
  }
  // Billing UA — не должен уходить на /auto/.
  if (t == 'Lampa-Mobile' || RegExp(r'^Lampa-Mobile/\d').hasMatch(t)) {
    return true;
  }
  // До ребренда consumer-сборки.
  if (t.startsWith('LxBox-android')) return true;
  return false;
}

// §219 — module-level: раньше компилился на каждый вызов _sanitizeToken
// (в т.ч. при инициализации приложения).

/// Чистая функция-конструктор UA. Подставляет версию и гарантирует инварианты
/// независимо от мусора на входе. Вынесена отдельно ради regression-теста.
String buildSubscriptionUserAgent({required String appVersion}) {
  return _kProductToken;
}

/// Срезает ведущий `v` и символы, которые сломали бы структуру UA (скобки /
/// точка-с-запятой / пробелы). На пустом результате — [fallback], чтобы
/// инварианты держались даже до инициализации версии.
/// Резолвит UA из версии приложения ([VersionInfo], инициализируется в `main()`
/// до `runApp`). Синхронно — runtime-источников за пределами версии больше нет.
String resolveSubscriptionUserAgent() =>
    buildSubscriptionUserAgent(appVersion: VersionInfo.I.version);
