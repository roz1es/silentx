export type ChatType = 'direct' | 'group' | 'channel';

export type MessageMediaKind = 'image' | 'file' | 'voice' | 'video_note';

export interface MessageMedia {
  kind: MessageMediaKind;
  dataUrl: string;
  fileName?: string;
  mimeType?: string;
  durationMs?: number;
}

export interface EncryptedTextRecipient {
  userId: string;
  deviceId: string;
  nonce: string;
  ciphertext: string;
}

export interface EncryptedTextEnvelope {
  version: 1;
  algorithm: 'crypto_box_curve25519xsalsa20poly1305';
  senderDeviceId: string;
  /** Публичный ключ устройства отправителя на момент отправки. */
  senderPublicKey?: string;
  recipients: EncryptedTextRecipient[];
}

export interface UserPrivacy {
  /** Показывать ли пользователя онлайн в статусах */
  showOnline?: boolean;
  /** Разрешать ли звонки от собеседников */
  allowCalls?: boolean;
  /** Показывать ли почту в профиле другим пользователям */
  showEmail?: boolean;
}

export interface User {
  id: string;
  username: string;
  password: string;
  email?: string;
  emailVerified?: boolean;
  avatarUrl?: string;
  /** Отображаемое имя в чатах; если пусто — username */
  displayName?: string;
  bio?: string;
  phone?: string;
  /** YYYY-MM-DD */
  birthDate?: string;
  /** Доступ к /api/admin и админ-панели */
  isAdmin?: boolean;
  /** Заблокирован администратором */
  banned?: boolean;
  privacy?: UserPrivacy;
}

export interface LastMessagePreview {
  text: string;
  time: number;
  senderId: string;
}

export interface Chat {
  id: string;
  type: ChatType;
  name: string;
  /** Аватар группы / канала (data URL) */
  avatarUrl?: string;
  participantIds: string[];
  lastMessage?: LastMessagePreview | null;
  unread: Record<string, number>;
  /** Время последнего просмотренного сообщения (createdAt) для пользователя */
  lastReadAt?: Record<string, number>;
  /** Закреплённое для всех сообщение в чате */
  pinnedMessageId?: string | null;
  /** Канал: только этот пользователь может писать */
  channelOwnerId?: string;
  /** Канал: дополнительные пользователи с правом писать (администраторы) */
  channelAdminIds?: string[];
}

export interface Message {
  id: string;
  chatId: string;
  senderId: string;
  text: string;
  encryptedText?: EncryptedTextEnvelope;
  imageUrl?: string;
  media?: MessageMedia;
  createdAt: number;
  deleted?: boolean;
  /** Время последнего редактирования текста */
  editedAt?: number;
  /** id сообщения, на которое отвечают */
  replyToMessageId?: string;
  /** emoji -> userIds */
  reactions?: Record<string, string[]>;
}
