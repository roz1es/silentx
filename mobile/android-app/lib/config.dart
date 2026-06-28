/// Конфигурация мобильного клиента BrenksChat.
///
/// Значения можно переопределить при сборке через --dart-define, например:
///   flutter run --dart-define=BRENKS_API_URL=https://api.brenkschat.ru
const defaultApiUrl = String.fromEnvironment(
  'BRENKS_API_URL',
  defaultValue: 'https://api.brenkschat.ru',
);

const appVersion = String.fromEnvironment(
  'BRENKS_APP_VERSION',
  defaultValue: '0.1.0',
);

/// Публичная ссылка на профиль (для QR и «Поделиться»). Ведёт на веб-клиент
/// (brenkschat.ru), а НЕ на API-домен (api.brenkschat.ru) — там пути /u/ нет.
String profileLink(String serverUrl, String username) {
  final uri = Uri.tryParse(serverUrl);
  if (uri == null || uri.host.isEmpty) {
    return '$serverUrl/u/$username';
  }
  var host = uri.host;
  if (host.startsWith('api.')) host = host.substring(4);
  final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
  final portPart =
      (uri.hasPort && uri.port != 80 && uri.port != 443) ? ':${uri.port}' : '';
  return '$scheme://$host$portPart/u/$username';
}

/// Нормализует адрес сервера: убирает завершающий слэш и добавляет схему.
String normalizeServerUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return defaultApiUrl;
  final withoutTrailingSlash = trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  if (withoutTrailingSlash.startsWith('http://') ||
      withoutTrailingSlash.startsWith('https://')) {
    return withoutTrailingSlash;
  }
  return 'https://$withoutTrailingSlash';
}
