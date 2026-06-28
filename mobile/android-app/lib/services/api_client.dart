import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Результат входа или регистрации.
///
/// Либо успех с пользователем и токеном, либо требование ввести код,
/// присланный на почту (для логина и для регистрации).
class AuthResult {
  const AuthResult.success({
    required this.user,
    required this.token,
  })  : ticket = null,
        emailMasked = null,
        codeRequired = false;

  const AuthResult.codeRequired({
    required this.ticket,
    required this.emailMasked,
  })  : user = null,
        token = null,
        codeRequired = true;

  final User? user;
  final String? token;
  final String? ticket;
  final String? emailMasked;
  final bool codeRequired;
}

/// Результат запроса на сброс пароля.
class PasswordResetRequestResult {
  const PasswordResetRequestResult({
    this.ticket,
    this.emailMasked,
    this.message,
  });

  final String? ticket;
  final String? emailMasked;
  final String? message;

  bool get codeSent => ticket != null && ticket!.isNotEmpty;
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.token,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  String baseUrl;
  String? token;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// Преобразует относительный путь медиа/аватара в абсолютный URL.
  String? resolveUrl(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty || raw.startsWith('data:')) return raw;
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    if (uri.hasScheme) return raw;
    return Uri.parse(baseUrl).resolve(raw).toString();
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final encodedBody = body == null ? null : jsonEncode(body);
    late final http.Response response;
    try {
      response = await switch (method) {
        'POST' => _http
            .post(_uri(path), headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20)),
        'PATCH' => _http
            .patch(_uri(path), headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20)),
        'DELETE' => _http
            .delete(_uri(path), headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20)),
        _ => _http
            .get(_uri(path), headers: headers)
            .timeout(const Duration(seconds: 20)),
      };
    } on TimeoutException {
      throw ApiException('Сервер долго не отвечает.');
    } on Object catch (err) {
      throw ApiException('Не удалось подключиться к серверу: $err');
    }

    Map<String, dynamic> parsed;
    try {
      parsed = response.body.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(response.body) as Map).cast<String, dynamic>();
    } on Object {
      parsed = <String, dynamic>{
        'error': 'Сервер вернул неожиданный ответ.',
      };
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
          parsed['error']?.toString() ?? response.reasonPhrase ?? 'Ошибка API');
    }

    return parsed;
  }

  /// ICE-серверы (STUN/TURN) для звонков. Контракт совпадает с веб-клиентом.
  Future<List<Map<String, dynamic>>> fetchCallIceServers() async {
    final res = await _request('/api/calls/ice-servers');
    final list = res['iceServers'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  // --- Авторизация ---

  Future<AuthResult> login({
    required String username,
    required String password,
    bool rememberMe = true,
  }) async {
    final json = await _request(
      '/api/login',
      method: 'POST',
      body: {
        'username': username,
        'password': password,
        'rememberMe': rememberMe,
      },
    );

    if (json['emailCodeRequired'] == true) {
      return AuthResult.codeRequired(
        ticket: json['ticket']?.toString() ?? '',
        emailMasked: json['emailMasked']?.toString() ?? '',
      );
    }

    return AuthResult.success(
      user: User.fromJson((json['user'] as Map).cast<String, dynamic>()),
      token: json['token']?.toString() ?? '',
    );
  }

  Future<AuthResult> confirmLogin({
    required String ticket,
    required String code,
    bool rememberMe = true,
  }) async {
    final json = await _request(
      '/api/login/confirm',
      method: 'POST',
      body: {
        'ticket': ticket,
        'code': code,
        'rememberMe': rememberMe,
      },
    );

    return AuthResult.success(
      user: User.fromJson((json['user'] as Map).cast<String, dynamic>()),
      token: json['token']?.toString() ?? '',
    );
  }

  /// Регистрация. Сервер всегда отправляет код подтверждения на почту.
  Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final json = await _request(
      '/api/register',
      method: 'POST',
      body: {
        'username': username,
        'email': email,
        'password': password,
      },
    );

    return AuthResult.codeRequired(
      ticket: json['ticket']?.toString() ?? '',
      emailMasked: json['emailMasked']?.toString() ?? '',
    );
  }

  Future<AuthResult> confirmRegister({
    required String ticket,
    required String code,
  }) async {
    final json = await _request(
      '/api/register/confirm',
      method: 'POST',
      body: {
        'ticket': ticket,
        'code': code,
      },
    );

    return AuthResult.success(
      user: User.fromJson((json['user'] as Map).cast<String, dynamic>()),
      token: json['token']?.toString() ?? '',
    );
  }

  Future<PasswordResetRequestResult> requestPasswordReset(String login) async {
    final json = await _request(
      '/api/password-reset/request',
      method: 'POST',
      body: {'login': login},
    );
    return PasswordResetRequestResult(
      ticket: json['ticket']?.toString(),
      emailMasked: json['emailMasked']?.toString(),
      message: json['message']?.toString(),
    );
  }

  Future<void> confirmPasswordReset({
    required String ticket,
    required String code,
    required String password,
  }) async {
    await _request(
      '/api/password-reset/confirm',
      method: 'POST',
      body: {
        'ticket': ticket,
        'code': code,
        'password': password,
      },
    );
  }

  Future<void> logout() async {
    await _request('/api/logout', method: 'POST', body: const {});
  }

  // --- Профиль и пользователи ---

  Future<User> fetchMe() async {
    final json = await _request('/api/me');
    return User.fromJson((json['user'] as Map).cast<String, dynamic>());
  }

  Future<List<DirectoryUser>> fetchUserDirectory() async {
    final json = await _request('/api/users/directory');
    final users = json['users'];
    if (users is! List) return const [];
    return users
        .whereType<Map>()
        .map((item) => DirectoryUser.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<User> fetchUserProfile(String userId) async {
    final json = await _request('/api/users/${Uri.encodeComponent(userId)}');
    return User.fromJson((json['user'] as Map).cast<String, dynamic>());
  }

  /// Только контакты (пользователи, с кем есть чат) — для приглашения в
  /// группы/каналы. Не весь каталог (его видят только админы).
  Future<List<DirectoryUser>> fetchContacts() async {
    final json = await _request('/api/users/contacts');
    final users = json['users'];
    if (users is! List) return const [];
    return users
        .whereType<Map>()
        .map((e) => DirectoryUser.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Поиск пользователей по юзернейму/имени (для создания личного чата).
  Future<List<DirectoryUser>> searchUsers(String query) async {
    final json =
        await _request('/api/users/search?q=${Uri.encodeComponent(query)}');
    final users = json['users'];
    if (users is! List) return const [];
    return users
        .whereType<Map>()
        .map((e) => DirectoryUser.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<User> updateProfile({
    String? displayName,
    String? avatarDataUrl,
    String? bio,
    String? phone,
    String? birthDate,
    bool? showOnline,
    bool? allowCalls,
    bool? showEmail,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (avatarDataUrl != null) body['avatarUrl'] = avatarDataUrl;
    if (bio != null) body['bio'] = bio;
    if (phone != null) body['phone'] = phone;
    if (birthDate != null) body['birthDate'] = birthDate;
    if (showOnline != null && allowCalls != null && showEmail != null) {
      body['privacy'] = {
        'showOnline': showOnline,
        'allowCalls': allowCalls,
        'showEmail': showEmail,
      };
    }
    final json = await _request('/api/me', method: 'PATCH', body: body);
    return User.fromJson((json['user'] as Map).cast<String, dynamic>());
  }

  Future<void> removeAvatar() async {
    await _request('/api/me', method: 'PATCH', body: {'avatarUrl': null});
  }

  Future<List<UserSession>> fetchSessions() async {
    final json = await _request('/api/me/sessions');
    final list = json['sessions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => UserSession.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> revokeSession(String sessionId) async {
    await _request('/api/me/sessions/${Uri.encodeComponent(sessionId)}',
        method: 'DELETE');
  }

  Future<void> revokeOtherSessions() async {
    await _request('/api/me/sessions/revoke-others',
        method: 'POST', body: const {});
  }

  // --- Чаты ---

  Future<List<Chat>> fetchChats() async {
    final json = await _request('/api/chats');
    final chats = json['chats'];
    if (chats is! List) return const [];
    return chats
        .whereType<Map>()
        .map((item) => Chat.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Последние сообщения чата (по умолчанию 80). [before] — createdAt самого
  /// старого загруженного сообщения для подгрузки истории при скролле вверх.
  Future<List<Message>> fetchMessages(String chatId,
      {int limit = 80, int? before}) async {
    final query = StringBuffer('?limit=$limit');
    if (before != null) query.write('&before=$before');
    final json = await _request(
        '/api/chats/${Uri.encodeComponent(chatId)}/messages$query');
    final messages = json['messages'];
    if (messages is! List) return const [];
    return messages
        .whereType<Map>()
        .map((item) => Message.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Выдать/снять галочку каналу (только админ). Возвращает обновлённый чат.
  Future<Chat> setChannelVerified(String chatId, bool verified) async {
    final json = await _request(
      '/api/admin/chats/${Uri.encodeComponent(chatId)}/verified',
      method: 'POST',
      body: {'verified': verified},
    );
    return Chat.fromJson((json['chat'] as Map).cast<String, dynamic>());
  }

  Future<Chat> createDirectChat({required String targetUserId}) async {
    final json = await _request(
      '/api/chats/direct',
      method: 'POST',
      body: {'targetUserId': targetUserId},
    );
    return Chat.fromJson((json['chat'] as Map).cast<String, dynamic>());
  }

  Future<Chat> createGroupChat({
    required String name,
    required List<String> memberIds,
  }) async {
    final json = await _request(
      '/api/chats/group',
      method: 'POST',
      body: {
        'name': name,
        'memberIds': memberIds,
      },
    );
    return Chat.fromJson((json['chat'] as Map).cast<String, dynamic>());
  }

  Future<Chat> createChannelChat({
    required String name,
    required List<String> subscriberIds,
  }) async {
    final json = await _request(
      '/api/chats/channel',
      method: 'POST',
      body: {
        'name': name,
        'memberIds': subscriberIds,
      },
    );
    return Chat.fromJson((json['chat'] as Map).cast<String, dynamic>());
  }

  Future<void> setPinnedMessage({
    required String chatId,
    required String? messageId,
  }) async {
    await _request(
      '/api/chats/${Uri.encodeComponent(chatId)}/pin-message',
      method: 'POST',
      body: {'messageId': messageId},
    );
  }

  Future<void> setChatMuted({
    required String chatId,
    required bool muted,
  }) async {
    await _request(
      '/api/chats/${Uri.encodeComponent(chatId)}/mute',
      method: 'POST',
      body: {'muted': muted},
    );
  }

  Future<void> setChatPinnedTop({
    required String chatId,
    required bool pinned,
  }) async {
    await _request(
      '/api/chats/${Uri.encodeComponent(chatId)}/pin-top',
      method: 'POST',
      body: {'pinned': pinned},
    );
  }

  Future<void> clearChat(String chatId) async {
    await _request(
      '/api/chats/${Uri.encodeComponent(chatId)}/clear',
      method: 'POST',
      body: const {},
    );
  }

  Future<void> deleteChat(String chatId) async {
    await _request(
      '/api/chats/${Uri.encodeComponent(chatId)}',
      method: 'DELETE',
    );
  }

  void dispose() {
    _http.close();
  }
}
