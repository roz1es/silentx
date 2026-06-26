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
  /** Публичный ключ устройства отправителя на момент отправки.
   * Нужен для расшифровки старых сообщений, даже если устройство уже не в каталоге.
   */
  senderPublicKey?: string;
  recipients: EncryptedTextRecipient[];
}

export interface UserPrivacy {
  showOnline?: boolean;
  allowCalls?: boolean;
  showEmail?: boolean;
}

export interface User {
  id: string;
  username: string;
  email?: string;
  emailVerified?: boolean;
  avatarUrl?: string;
  displayName?: string;
  bio?: string;
  phone?: string;
  /** YYYY-MM-DD */
  birthDate?: string;
  /** Только у служебной учётки администратора */
  isAdmin?: boolean;
  banned?: boolean;
  privacy?: UserPrivacy;
}

export interface ChatParticipant {
  id: string;
  username: string;
  displayName?: string;
  avatarUrl?: string;
  privacy?: UserPrivacy;
}

export interface Chat {
  id: string;
  type: ChatType;
  name: string;
  avatarUrl?: string;
  participantIds: string[];
  participants?: ChatParticipant[];
  displayName?: string;
  lastMessage?: {
    text: string;
    time: number;
    senderId: string;
  } | null;
  unread: Record<string, number>;
  lastReadAt?: Record<string, number>;
  pinnedMessageId?: string | null;
  /** Канал: id владельца (единственный, кто пишет) */
  channelOwnerId?: string;
  /** Канал подтвержден администрацией */
  verified?: boolean;
  /** Локально для пользователя */
  muted?: boolean;
  pinnedToTop?: boolean;
}

export interface Message {
  id: string;
  chatId: string;
  senderId: string;
  text: string;
  encryptedText?: EncryptedTextEnvelope;
  /** Вычисляется только на устройстве после локальной расшифровки. */
  encryptionState?: 'encrypted' | 'pending' | 'recovering' | 'failed';
  imageUrl?: string;
  media?: MessageMedia;
  createdAt: number;
  deleted?: boolean;
  editedAt?: number;
  replyToMessageId?: string;
  reactions?: Record<string, string[]>;
}

export interface TypingState {
  userId: string;
  isTyping: boolean;
}
