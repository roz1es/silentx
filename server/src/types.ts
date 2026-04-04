export type ChatType = 'direct' | 'group';

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
  password: string;
  avatarUrl?: string;
  /** Отображаемое имя в чатах; если пусто — username */
  displayName?: string;
  bio?: string;
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
  participantIds: string[];
  lastMessage?: LastMessagePreview;
  unread: Record<string, number>;
  /** Время последнего просмотренного сообщения (createdAt) для пользователя */
  lastReadAt?: Record<string, number>;
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
}
