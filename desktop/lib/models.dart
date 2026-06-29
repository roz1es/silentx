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
    this.bio,
    this.phone,
    this.birthDate,
    this.privacy = const UserPrivacy(),
    this.blockedUserIds = const [],
    this.blockedByViewer = false,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? email;
  final bool emailVerified;
  final bool isAdmin;
  final String? bio;
  final String? phone;
  final String? birthDate;
  final UserPrivacy privacy;
  final List<String> blockedUserIds;
  final bool blockedByViewer;

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
      bio: json['bio']?.toString(),
      phone: json['phone']?.toString(),
      birthDate: json['birthDate']?.toString(),
      privacy: json['privacy'] is Map
          ? UserPrivacy.fromJson(
              (json['privacy'] as Map).cast<String, dynamic>())
          : const UserPrivacy(),
      blockedUserIds: json['blockedUserIds'] is List
          ? (json['blockedUserIds'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
          : const [],
      blockedByViewer: json['blockedByViewer'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      if (displayName != null) 'displayName': displayName,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (email != null) 'email': email,
      'emailVerified': emailVerified,
      'isAdmin': isAdmin,
      if (bio != null) 'bio': bio,
      if (phone != null) 'phone': phone,
      if (birthDate != null) 'birthDate': birthDate,
      'privacy': privacy.toJson(),
      'blockedUserIds': blockedUserIds,
      'blockedByViewer': blockedByViewer,
    };
  }
}

class UserPrivacy {
  const UserPrivacy({
    this.showOnline = true,
    this.allowMessages = true,
    this.allowCalls = true,
    this.showEmail = false,
  });

  final bool showOnline;
  final bool allowMessages;
  final bool allowCalls;
  final bool showEmail;

  factory UserPrivacy.fromJson(Map<String, dynamic> json) {
    return UserPrivacy(
      showOnline: json['showOnline'] != false,
      allowMessages: json['allowMessages'] != false,
      allowCalls: json['allowCalls'] != false,
      showEmail: json['showEmail'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'showOnline': showOnline,
      'allowMessages': allowMessages,
      'allowCalls': allowCalls,
      'showEmail': showEmail,
    };
  }
}

class ChatParticipant {
  const ChatParticipant({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.blockedByViewer = false,
    this.privacy = const UserPrivacy(),
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final bool blockedByViewer;
  final UserPrivacy privacy;

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
      blockedByViewer: json['blockedByViewer'] == true,
      privacy: json['privacy'] is Map
          ? UserPrivacy.fromJson(
              (json['privacy'] as Map).cast<String, dynamic>())
          : const UserPrivacy(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      if (displayName != null) 'displayName': displayName,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'blockedByViewer': blockedByViewer,
      'privacy': privacy.toJson(),
    };
  }
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
    this.pinnedMessageId,
    this.channelOwnerId,
    this.channelAdminIds = const [],
    this.muted = false,
    this.pinnedToTop = false,
    this.verified = false,
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
  final String? pinnedMessageId;
  final String? channelOwnerId;
  final List<String> channelAdminIds;
  final bool muted;
  final bool pinnedToTop;
  final bool verified;

  String get title {
    final custom = displayName?.trim();
    return custom == null || custom.isEmpty ? name : custom;
  }

  ChatParticipant? peerFor(String viewerId) {
    if (type != ChatType.direct) return null;
    for (final participant in participants) {
      if (participant.id != viewerId) return participant;
    }
    return null;
  }

  String titleFor(String viewerId) {
    final peer = peerFor(viewerId);
    return peer?.title ?? title;
  }

  String? avatarFor(String viewerId) {
    final peer = peerFor(viewerId);
    return peer?.avatarUrl ?? avatarUrl;
  }

  bool canPost(String viewerId) {
    if (type != ChatType.channel) return true;
    return channelOwnerId == viewerId || channelAdminIds.contains(viewerId);
  }

  bool canManageChannel(String viewerId) {
    return type == ChatType.channel && channelOwnerId == viewerId;
  }

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
      pinnedMessageId: json['pinnedMessageId']?.toString(),
      channelOwnerId: json['channelOwnerId']?.toString(),
      channelAdminIds: json['channelAdminIds'] is List
          ? (json['channelAdminIds'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
          : const [],
      muted: json['muted'] == true,
      pinnedToTop: json['pinnedToTop'] == true,
      verified: json['verified'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      if (displayName != null) 'displayName': displayName,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'participantIds': participantIds,
      'participants': participants.map((item) => item.toJson()).toList(),
      if (lastMessage != null) 'lastMessage': lastMessage!.toJson(),
      'unread': unread,
      if (pinnedMessageId != null) 'pinnedMessageId': pinnedMessageId,
      if (channelOwnerId != null) 'channelOwnerId': channelOwnerId,
      'channelAdminIds': channelAdminIds,
      'muted': muted,
      'pinnedToTop': pinnedToTop,
      'verified': verified,
    };
  }
}

class DirectoryUser {
  const DirectoryUser({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.blockedByViewer = false,
    this.privacy = const UserPrivacy(),
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final bool blockedByViewer;
  final UserPrivacy privacy;

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
      blockedByViewer: json['blockedByViewer'] == true,
      privacy: json['privacy'] is Map
          ? UserPrivacy.fromJson(
              (json['privacy'] as Map).cast<String, dynamic>())
          : const UserPrivacy(),
    );
  }
}

class AdminUserRow {
  const AdminUserRow({
    required this.id,
    required this.username,
    required this.emailVerified,
    required this.isAdmin,
    required this.banned,
    required this.messageCount,
    required this.chatCount,
    this.displayName,
    this.email,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? email;
  final bool emailVerified;
  final bool isAdmin;
  final bool banned;
  final int messageCount;
  final int chatCount;

  String get title {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? username : name;
  }

  factory AdminUserRow.fromJson(Map<String, dynamic> json) {
    return AdminUserRow(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
      email: json['email']?.toString(),
      emailVerified: json['emailVerified'] == true,
      isAdmin: json['isAdmin'] == true,
      banned: json['banned'] == true,
      messageCount: _intFromJson(json['messageCount']),
      chatCount: _intFromJson(json['chatCount']),
    );
  }
}

class AdminOverview {
  const AdminOverview({
    required this.userCount,
    required this.blockedUserCount,
    required this.openReportCount,
    required this.chatCount,
    required this.directChatCount,
    required this.groupChatCount,
    required this.channelChatCount,
    required this.messageCount,
    required this.users,
  });

  final int userCount;
  final int blockedUserCount;
  final int openReportCount;
  final int chatCount;
  final int directChatCount;
  final int groupChatCount;
  final int channelChatCount;
  final int messageCount;
  final List<AdminUserRow> users;

  factory AdminOverview.fromJson(Map<String, dynamic> json) {
    final users = json['users'];
    return AdminOverview(
      userCount: _intFromJson(json['userCount']),
      blockedUserCount: _intFromJson(json['blockedUserCount']),
      openReportCount: _intFromJson(json['openReportCount']),
      chatCount: _intFromJson(json['chatCount']),
      directChatCount: _intFromJson(json['directChatCount']),
      groupChatCount: _intFromJson(json['groupChatCount']),
      channelChatCount: _intFromJson(json['channelChatCount']),
      messageCount: _intFromJson(json['messageCount']),
      users: users is List
          ? users
              .whereType<Map>()
              .map(
                  (item) => AdminUserRow.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false)
          : const [],
    );
  }
}

class UserReport {
  const UserReport({
    required this.id,
    required this.reporterId,
    required this.targetUserId,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.chatId,
    this.messageId,
    this.comment,
    this.closedBy,
    this.reporter,
    this.target,
  });

  final String id;
  final String reporterId;
  final String targetUserId;
  final String? chatId;
  final String? messageId;
  final String reason;
  final String? comment;
  final String status;
  final int createdAt;
  final int updatedAt;
  final String? closedBy;
  final ChatParticipant? reporter;
  final ChatParticipant? target;

  factory UserReport.fromJson(Map<String, dynamic> json) {
    return UserReport(
      id: json['id']?.toString() ?? '',
      reporterId: json['reporterId']?.toString() ?? '',
      targetUserId: json['targetUserId']?.toString() ?? '',
      chatId: json['chatId']?.toString(),
      messageId: json['messageId']?.toString(),
      reason: json['reason']?.toString() ?? 'Другая причина',
      comment: json['comment']?.toString(),
      status: json['status']?.toString() ?? 'open',
      createdAt: _intFromJson(json['createdAt']),
      updatedAt: _intFromJson(json['updatedAt']),
      closedBy: json['closedBy']?.toString(),
      reporter: json['reporter'] is Map
          ? ChatParticipant.fromJson(
              (json['reporter'] as Map).cast<String, dynamic>())
          : null,
      target: json['target'] is Map
          ? ChatParticipant.fromJson(
              (json['target'] as Map).cast<String, dynamic>())
          : null,
    );
  }
}

class AuthSessionInfo {
  const AuthSessionInfo({
    required this.id,
    required this.createdAt,
    required this.expiresAt,
    required this.current,
    required this.remembered,
  });

  final String id;
  final int createdAt;
  final int expiresAt;
  final bool current;
  final bool remembered;

  factory AuthSessionInfo.fromJson(Map<String, dynamic> json) {
    return AuthSessionInfo(
      id: json['id']?.toString() ?? '',
      createdAt: _intFromJson(json['createdAt']),
      expiresAt: _intFromJson(json['expiresAt']),
      current: json['current'] == true,
      remembered: json['remembered'] == true,
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

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'time': time,
      'senderId': senderId,
    };
  }
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
    this.encryptedText = false,
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
  final bool encryptedText;
  final String? imageUrl;
  final MessageMedia? media;
  final bool deleted;
  final int? editedAt;
  final String? replyToMessageId;
  final Map<String, List<String>> reactions;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id']?.toString() ?? '',
      chatId: json['chatId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      createdAt: _intFromJson(json['createdAt']),
      encryptedText: json['encryptedText'] != null,
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'createdAt': createdAt,
      if (encryptedText) 'encryptedText': true,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (media != null) 'media': media!.toJson(),
      if (deleted) 'deleted': deleted,
      if (editedAt != null) 'editedAt': editedAt,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (reactions.isNotEmpty) 'reactions': reactions,
    };
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
