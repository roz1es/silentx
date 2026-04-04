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
  avatarUrl?: string;
  displayName?: string;
  bio?: string;
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

export interface TypingState {
  userId: string;
  isTyping: boolean;
}
