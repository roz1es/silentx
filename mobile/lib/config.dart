/// Конфигурация мобильного клиента BrenksChat.
///
/// Значения можно переопределить при сборке через --dart-define, например:
///   flutter run --dart-define=BRENKS_API_URL=https://silentx.ru
const defaultApiUrl = String.fromEnvironment(
  'BRENKS_API_URL',
  defaultValue: 'https://silentx.ru',
);

const appVersion = String.fromEnvironment(
  'BRENKS_APP_VERSION',
  defaultValue: '0.1.0',
);

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
