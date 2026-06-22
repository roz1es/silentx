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
        _ => _http
            .get(_uri(path), headers: headers)
            .timeout(const Duration(seconds: 20)),
      };
    } on TimeoutException {
      throw ApiException('Сервер долго не отвечает.');
    } on Object catch (err) {
      throw ApiException('Не удалось подключиться к серверу: $err');
    }

    final parsed = response.body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(response.body) as Map).cast<String, dynamic>();

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

    return AuthResult.success(
      user: User.fromJson((json['user'] as Map).cast<String, dynamic>()),
      token: json['token']?.toString() ?? '',
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

    return AuthResult.success(
      user: User.fromJson((json['user'] as Map).cast<String, dynamic>()),
      token: json['token']?.toString() ?? '',
    );
  }

  Future<User> fetchMe() async {
    final json = await _request('/api/me');
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

  Future<List<Message>> fetchMessages(String chatId) async {
    final json =
        await _request('/api/chats/${Uri.encodeComponent(chatId)}/messages');
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
