import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Сохранить картинку в галерею устройства (Pictures/BrenksChat).
/// Возвращает true при успехе.
Future<bool> saveImageToGallery(Uint8List bytes, String name,
    {String mime = 'image/jpeg'}) async {
  try {
    final ok = await NotificationService._channel.invokeMethod<bool>(
      'saveImage',
      {'bytes': bytes, 'name': name, 'mime': mime},
    );
    return ok == true;
  } on Object {
    return false;
  }
}

/// Открыть http(s)-ссылку во внешнем браузере через натив (без url_launcher).
Future<void> openExternalUrl(String url) async {
  try {
    await NotificationService._channel
        .invokeMethod<void>('openUrl', {'url': url});
  } on Object {
    // Натив недоступен — молча пропускаем.
  }
}

/// Локальные уведомления о сообщениях (без Firebase): натив показывает их
/// через MethodChannel, пока живо соединение с сокетом. Показываем, когда
/// приложение свёрнуто или открыт другой чат.
class NotificationService with WidgetsBindingObserver {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channel = MethodChannel('brenks/notifications');

  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// Приложение сейчас на экране.
  bool get inForeground => _lifecycle == AppLifecycleState.resumed;

  /// Подключает наблюдение за жизненным циклом и запрашивает разрешение
  /// на уведомления (Android 13+). Вызывается один раз в main().
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await _channel.invokeMethod<void>('requestPermission');
    } on Object {
      // Натив недоступен (iOS/тесты) — просто без уведомлений.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      // Вернулись в приложение — прибираем шторку.
      _channel.invokeMethod<void>('cancelAll').catchError((_) {});
    }
  }

  /// Показывает уведомление о новом сообщении. [id] — стабильный на чат,
  /// чтобы сообщения одного чата заменяли друг друга, а не копились.
  Future<void> showMessage({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'id': id,
        'title': title,
        'body': body,
      });
    } on Object {
      // Нет натива — молча пропускаем.
    }
  }
}
