const defaultApiUrl = String.fromEnvironment(
  'BRENKS_API_URL',
  defaultValue: 'https://silentx.ru',
);

const appVersion = String.fromEnvironment(
  'BRENKS_APP_VERSION',
  defaultValue: '0.1.0',
);

const updateManifestUrl = String.fromEnvironment(
  'BRENKS_UPDATE_URL',
  defaultValue: 'https://silentx.ru/desktop/windows/latest.json',
);

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

int compareVersions(String left, String right) {
  final leftParts =
      left.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final rightParts =
      right.split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var i = 0; i < maxLength; i += 1) {
    final a = i < leftParts.length ? leftParts[i] : 0;
    final b = i < rightParts.length ? rightParts[i] : 0;
    if (a != b) return a.compareTo(b);
  }
  return 0;
}
