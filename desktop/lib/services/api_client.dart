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

class AuthResult {
  const AuthResult.success({
    required this.user,
    required this.token,
  })  : ticket = null,
        emailMasked = null,
        emailCodeRequired = false;

  const AuthResult.emailCodeRequired({
    required this.ticket,
    required this.emailMasked,
  })  : user = null,
        token = null,
        emailCodeRequired = true;

  final User? user;
  final String? token;
  final String? ticket;
  final String? emailMasked;
  final bool emailCodeRequired;
}

class PasswordResetRequestResult {
  const PasswordResetRequestResult({
    required this.ticket,
    required this.emailMasked,
    required this.message,
  });

  final String? ticket;
  final String? emailMasked;
  final String? message;
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
        'DELETE' => _http
            .delete(_uri(path), headers: headers, body: encodedBody)
            .timeout(const Duration(seconds: 20)),
        'PATCH' => _http
            .patch(_uri(path), headers: headers, body: encodedBody)
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

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final json = await _request(
      '/api/login',
      method: 'POST',
      body: {
        'username': username,
        'password': password,
      },
    );

    if (json['emailCodeRequired'] == true) {
      return AuthResult.emailCodeRequired(
        ticket: json['ticket']?.toString() ?? '',
        emailMasked: json['emailMasked']?.toString() ?? '',
      );
    }

    final token = json['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw ApiException('Сервер не вернул токен авторизации.');
    }

    return AuthResult.success(
      user: User.fromJson((json['user'] as Map).cast<String, dynamic>()),
      token: token,
    );
  }

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

    if (json['emailVerificationRequired'] == true) {
      return AuthResult.emailCodeRequired(
        ticket: json['ticket']?.toString() ?? '',
        emailMasked: json['emailMasked']?.toString() ?? '',
      );
    }

    final token = json['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw ApiException('Сервер не вернул токен авторизации.');
    }

    return AuthResult.success(
      user: User.fromJson((json['user'] as Map).cast<String, dynamic>()),
      token: token,
    );
  }

  Future<AuthResult> confirmLogin({
    required String ticket,
    required String code,
  }) async {
    final json = await _request(
      '/api/login/confirm',
      method: 'POST',
      body: {
        'ticket': ticket,
        'code': code,
      },
    );

    final token = json['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw ApiException('Сервер не вернул токен авторизации.');
    }

    return AuthResult.success(
      user: User.fromJson((json['user'] as Map).cast<String, dynamic>()),
      token: token,
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

    final token = json['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw ApiException('Сервер не вернул токен авторизации.');
    }

    return AuthResult.success(
      user: User.fromJson((json['user'] as Map).cast<String, dynamic>()),
      token: token,
    );
  }

  Future<PasswordResetRequestResult> requestPasswordReset({
    required String login,
  }) async {
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

  Future<User> fetchMe() async {
    final json = await _request('/api/me');
    return User.fromJson((json['user'] as Map).cast<String, dynamic>());
  }

  Future<User> updateProfile({
    String? displayName,
    Object? avatarUrl = _unchanged,
  }) async {
    final body = <String, Object?>{};
    if (displayName != null) body['displayName'] = displayName;
    if (!identical(avatarUrl, _unchanged)) body['avatarUrl'] = avatarUrl;
    final json = await _request('/api/me', method: 'PATCH', body: body);
    return User.fromJson((json['user'] as Map).cast<String, dynamic>());
  }

  Future<List<Chat>> fetchChats() async {
    final json = await _request('/api/chats');
    final chats = json['chats'];
    if (chats is! List) return const [];
    return chats
        .whereType<Map>()
        .map((item) => Chat.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<Message>> fetchMessages(
    String chatId, {
    int limit = 80,
    int? before,
  }) async {
    final query = <String, String>{
      'limit': limit.toString(),
      if (before != null) 'before': before.toString(),
    };
    final uri = Uri(
      path: '/api/chats/${Uri.encodeComponent(chatId)}/messages',
      queryParameters: query,
    );
    final json = await _request(uri.toString());
    final messages = json['messages'];
    if (messages is! List) return const [];
    return messages
        .whereType<Map>()
        .map((item) => Message.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
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

  Future<List<DirectoryUser>> searchUsers(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final json = await _request(
      '/api/users/search?q=${Uri.encodeQueryComponent(trimmed)}',
    );
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

  Future<Chat> setChatVerified({
    required String chatId,
    required bool verified,
  }) async {
    final json = await _request(
      '/api/admin/chats/${Uri.encodeComponent(chatId)}/verified',
      method: 'POST',
      body: {'verified': verified},
    );
    return Chat.fromJson((json['chat'] as Map).cast<String, dynamic>());
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
}

const Object _unchanged = Object();
