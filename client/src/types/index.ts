export type ChatType = 'direct' | 'group' | 'channel';

export type MessageMediaKind = 'image' | 'file' | 'voice' | 'video_note';

export interface MessageMedia {
  kind: MessageMediaKind;
  dataUrl: string;
  fileName?: string;
  mimeType?: string;
  durationMs?: number;
}

export interface User {
  id: string;
  username: string;
  avatarUrl?: string;
  displayName?: string;
  bio?: string;
  phone?: string;
  /** YYYY-MM-DD */
  birthDate?: string;
  /** Только у служебной учётки администратора */
  isAdmin?: boolean;
}

export interface ChatParticipant {
  id: string;
  username: string;
  displayName?: string;
  avatarUrl?: string;
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
  };
  unread: Record<string, number>;
  lastReadAt?: Record<string, number>;
  pinnedMessageId?: string;
  /** Канал: id владельца (единственный, кто пишет) */
  channelOwnerId?: string;
  /** Локально для пользователя */
  muted?: boolean;
  pinnedToTop?: boolean;
}

export interface Message {
  id: string;
  chatId: string;
  senderId: string;
  text: string;
  imageUrl?: string;
  media?: MessageMedia;
  createdAt: number;
  deleted?: boolean;
  editedAt?: number;
}

export interface TypingState {
  userId: string;
  isTyping: boolean;
}
