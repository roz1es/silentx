enum ChatType {
  direct,
  group,
  channel;

  static ChatType fromJson(String? value) {
    return ChatType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ChatType.direct,
    );
  }
}

class User {
  const User({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.email,
    this.emailVerified = false,
    this.isAdmin = false,
    this.phone,
    this.bio,
    this.birthDate,
    this.showOnline = true,
    this.allowCalls = true,
    this.showEmail = false,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? email;
  final bool emailVerified;
  final bool isAdmin;
  final String? phone;
  final String? bio;
  final String? birthDate;
  final bool showOnline;
  final bool allowCalls;
  final bool showEmail;

  String get title {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? username : name;
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      email: json['email']?.toString(),
      emailVerified: json['emailVerified'] == true,
      isAdmin: json['isAdmin'] == true,
      phone: json['phone']?.toString(),
      bio: json['bio']?.toString(),
      birthDate: json['birthDate']?.toString(),
      showOnline: json['privacy'] is Map
          ? (json['privacy'] as Map)['showOnline'] != false
          : true,
      allowCalls: json['privacy'] is Map
          ? (json['privacy'] as Map)['allowCalls'] != false
          : true,
      showEmail: json['privacy'] is Map
          ? (json['privacy'] as Map)['showEmail'] == true
          : false,
    );
  }
}

class ChatParticipant {
  const ChatParticipant({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  String get title {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? username : name;
  }

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
      };
}

class Chat {
  const Chat({
    required this.id,
    required this.type,
    required this.name,
    this.displayName,
    this.avatarUrl,
    this.participantIds = const [],
    this.participants = const [],
    this.lastMessage,
    this.unread = const {},
    this.lastReadAt = const {},
    this.pinnedMessageId,
    this.muted = false,
    this.pinnedToTop = false,
    this.verified = false,
    this.channelOwnerId,
  });

  final String id;
  final ChatType type;
  final String name;
  final String? displayName;
  final String? avatarUrl;
  final List<String> participantIds;
  final List<ChatParticipant> participants;
  final LastMessage? lastMessage;
  final Map<String, int> unread;
  // userId → время последнего прочтения (для галочек «прочитано»).
  final Map<String, int> lastReadAt;
  final String? pinnedMessageId;
  final bool muted;
  final bool pinnedToTop;
  final bool verified;
  final String? channelOwnerId;

  String get title {
    final custom = displayName?.trim();
    return custom == null || custom.isEmpty ? name : custom;
  }

  Chat copyWith({
    LastMessage? lastMessage,
    Map<String, int>? unread,
    bool? muted,
    bool? pinnedToTop,
    bool? verified,
  }) {
    return Chat(
      id: id,
      type: type,
      name: name,
      displayName: displayName,
      avatarUrl: avatarUrl,
      participantIds: participantIds,
      participants: participants,
      lastMessage: lastMessage ?? this.lastMessage,
      unread: unread ?? this.unread,
      lastReadAt: lastReadAt,
      pinnedMessageId: pinnedMessageId,
      muted: muted ?? this.muted,
      pinnedToTop: pinnedToTop ?? this.pinnedToTop,
      verified: verified ?? this.verified,
      channelOwnerId: channelOwnerId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'participantIds': participantIds,
        'participants': participants.map((p) => p.toJson()).toList(),
        'lastMessage': lastMessage?.toJson(),
        'unread': unread,
        'lastReadAt': lastReadAt,
        'pinnedMessageId': pinnedMessageId,
        'muted': muted,
        'pinnedToTop': pinnedToTop,
        'verified': verified,
        'channelOwnerId': channelOwnerId,
      };

  factory Chat.fromJson(Map<String, dynamic> json) {
    final participantsJson = json['participants'];
    final idsJson = json['participantIds'];
    return Chat(
      id: json['id']?.toString() ?? '',
      type: ChatType.fromJson(json['type']?.toString()),
      name: json['name']?.toString() ?? 'Чат',
      displayName: json['displayName']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      participantIds: idsJson is List
          ? idsJson.map((item) => item.toString()).toList(growable: false)
          : const [],
      participants: participantsJson is List
          ? participantsJson
              .whereType<Map>()
              .map((item) => ChatParticipant.fromJson(
                    item.cast<String, dynamic>(),
                  ))
              .toList(growable: false)
          : const [],
      lastMessage: json['lastMessage'] is Map
          ? LastMessage.fromJson(
              (json['lastMessage'] as Map).cast<String, dynamic>(),
            )
          : null,
      unread: json['unread'] is Map
          ? (json['unread'] as Map).map(
              (key, value) => MapEntry(key.toString(), _intFromJson(value)),
            )
          : const {},
      lastReadAt: json['lastReadAt'] is Map
          ? (json['lastReadAt'] as Map).map(
              (key, value) => MapEntry(key.toString(), _intFromJson(value)),
            )
          : const {},
      pinnedMessageId: json['pinnedMessageId']?.toString(),
      muted: json['muted'] == true,
      pinnedToTop: json['pinnedToTop'] == true,
      verified: json['verified'] == true,
      channelOwnerId: json['channelOwnerId']?.toString(),
    );
  }
}

class DirectoryUser {
  const DirectoryUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  String get title {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? username : name;
  }

  factory DirectoryUser.fromJson(Map<String, dynamic> json) {
    return DirectoryUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
    );
  }
}

class LastMessage {
  const LastMessage({
    required this.text,
    required this.time,
    required this.senderId,
  });

  final String text;
  final int time;
  final String senderId;

  factory LastMessage.fromJson(Map<String, dynamic> json) {
    return LastMessage(
      text: json['text']?.toString() ?? '',
      time: _intFromJson(json['time']),
      senderId: json['senderId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'time': time,
        'senderId': senderId,
      };
}

class MessageMedia {
  const MessageMedia({
    required this.kind,
    required this.dataUrl,
    this.fileName,
    this.mimeType,
    this.durationMs,
  });

  final String kind;
  final String dataUrl;
  final String? fileName;
  final String? mimeType;
  final int? durationMs;

  factory MessageMedia.fromJson(Map<String, dynamic> json) {
    return MessageMedia(
      kind: json['kind']?.toString() ?? 'file',
      dataUrl: json['dataUrl']?.toString() ?? '',
      fileName: json['fileName']?.toString(),
      mimeType: json['mimeType']?.toString(),
      durationMs:
          json['durationMs'] == null ? null : _intFromJson(json['durationMs']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'dataUrl': dataUrl,
      if (fileName != null) 'fileName': fileName,
      if (mimeType != null) 'mimeType': mimeType,
      if (durationMs != null) 'durationMs': durationMs,
    };
  }
}

class Message {
  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.imageUrl,
    this.media,
    this.deleted = false,
    this.editedAt,
    this.replyToMessageId,
    this.reactions = const {},
  });

  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final int createdAt;
  final String? imageUrl;
  final MessageMedia? media;
  final bool deleted;
  final int? editedAt;
  final String? replyToMessageId;
  final Map<String, List<String>> reactions;

  /// Возвращает копию сообщения с заменой отдельных полей.
  Message copyWith({
    bool? deleted,
    String? text,
    int? editedAt,
    Map<String, List<String>>? reactions,
  }) {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      text: text ?? this.text,
      createdAt: createdAt,
      imageUrl: imageUrl,
      media: media,
      deleted: deleted ?? this.deleted,
      editedAt: editedAt ?? this.editedAt,
      replyToMessageId: replyToMessageId,
      reactions: reactions ?? this.reactions,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? '',
      chatId: json['chatId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: _intFromJson(json['createdAt']),
      imageUrl: json['imageUrl']?.toString(),
      media: json['media'] is Map
          ? MessageMedia.fromJson(
              (json['media'] as Map).cast<String, dynamic>())
          : null,
      deleted: json['deleted'] == true,
      editedAt:
          json['editedAt'] == null ? null : _intFromJson(json['editedAt']),
      replyToMessageId: json['replyToMessageId']?.toString(),
      reactions: _reactionsFromJson(json['reactions']),
    );
  }
}

Map<String, List<String>> _reactionsFromJson(Object? value) {
  if (value is! Map) return const {};
  final result = <String, List<String>>{};
  for (final entry in value.entries) {
    final users = entry.value;
    if (users is! List || users.isEmpty) continue;
    result[entry.key.toString()] =
        users.map((item) => item.toString()).toList(growable: false);
  }
  return result;
}

int _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
