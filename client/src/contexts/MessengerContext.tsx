import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { io, type Socket } from 'socket.io-client';
import type { Chat, Message, MessageMedia, User } from '@/types';
import * as api from '@/lib/api';
import { loadToken } from '@/lib/storage';
import { useAuth } from '@/contexts/AuthContext';

export type SendPayload = {
  text?: string;
  imageUrl?: string;
  media?: MessageMedia;
};

type MessengerContextValue = {
  chats: Chat[];
  activeChat: Chat | null;
  messages: Message[];
  onlineUserIds: string[];
  /** userId -> username для активного чата */
  typingNames: Record<string, string>;
  chatSearch: string;
  setChatSearch: (q: string) => void;
  selectChat: (id: string | null) => void;
  sendPayload: (p: SendPayload) => void;
  deleteMessage: (messageId: string) => void;
  notifyTyping: (isTyping: boolean) => void;
  refreshChats: () => Promise<void>;
  createDirect: (username: string) => Promise<void>;
  createGroup: (name: string, members: string[]) => Promise<void>;
  socketConnected: boolean;
};

const MessengerContext = createContext<MessengerContextValue | null>(null);

function playIncomingMessageSound() {
  try {
    const AC =
      window.AudioContext ||
      (window as unknown as { webkitAudioContext?: typeof AudioContext })
        .webkitAudioContext;
    if (!AC) return;
    const ctx = new AC();
    const go = () => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(880, ctx.currentTime);
      gain.gain.setValueAtTime(0.1, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.18);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + 0.18);
      osc.onended = () => {
        try {
          void ctx.close();
        } catch {
          /* noop */
        }
      };
    };
    if (ctx.state === 'suspended') void ctx.resume().then(go).catch(() => {});
    else go();
  } catch {
    /* autoplay / API */
  }
}

function notificationBody(m: Message): string {
  if (m.media) {
    switch (m.media.kind) {
      case 'file':
        return m.media.fileName ?? 'Файл';
      case 'voice':
        return 'Голосовое сообщение';
      case 'video_note':
        return 'Видеокружок';
      case 'image':
        return 'Фото';
      default:
        return 'Сообщение';
    }
  }
  if (m.imageUrl) return 'Фото';
  return m.text.trim() || 'Сообщение';
}

export function MessengerProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth() as { user: User };
  const [chats, setChats] = useState<Chat[]>([]);
  const [activeChatId, setActiveChatId] = useState<string | null>(null);
  const [messagesByChat, setMessagesByChat] = useState<Record<string, Message[]>>(
    {}
  );
  const [onlineUserIds, setOnlineUserIds] = useState<string[]>([]);
  const [typingNames, setTypingNames] = useState<Record<string, string>>({});
  const [chatSearch, setChatSearch] = useState('');
  const [socketConnected, setSocketConnected] = useState(false);

  const socketRef = useRef<Socket | null>(null);
  const activeChatIdRef = useRef<string | null>(null);
  const chatsRef = useRef<Chat[]>([]);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    activeChatIdRef.current = activeChatId;
  }, [activeChatId]);

  useEffect(() => {
    chatsRef.current = chats;
  }, [chats]);

  const activeChat = useMemo(
    () => chats.find((c) => c.id === activeChatId) ?? null,
    [chats, activeChatId]
  );

  const messages = activeChatId ? messagesByChat[activeChatId] ?? [] : [];

  const joinAllChats = useCallback((list: Chat[]) => {
    const s = socketRef.current;
    if (!s) return;
    list.forEach((c) => s.emit('join_chat', c.id));
  }, []);

  const refreshChats = useCallback(async () => {
    const { chats: list } = await api.fetchChats();
    setChats(list);
    joinAllChats(list);
  }, [joinAllChats]);

  useEffect(() => {
    refreshChats().catch(() => {});
  }, [refreshChats]);

  useEffect(() => {
    if (socketConnected && chats.length > 0) joinAllChats(chats);
  }, [socketConnected, chats, joinAllChats]);

  useEffect(() => {
    const token = loadToken();
    if (!token) {
      setSocketConnected(false);
      return;
    }

    const socket = io({
      path: '/socket.io',
      transports: ['websocket', 'polling'],
      autoConnect: true,
      auth: { token },
    });
    socketRef.current = socket;

    socket.on('connect', () => {
      setSocketConnected(true);
    });

    socket.on('disconnect', () => setSocketConnected(false));

    socket.on('presence', (payload: { onlineUserIds: string[] }) => {
      setOnlineUserIds(payload.onlineUserIds ?? []);
    });

    socket.on(
      'typing',
      (payload: {
        chatId: string;
        userId: string;
        username?: string;
        isTyping: boolean;
      }) => {
        if (payload.userId === user.id) return;
        if (payload.chatId !== activeChatIdRef.current) return;
        setTypingNames((prev) => {
          const next = { ...prev };
          if (payload.isTyping)
            next[payload.userId] = payload.username ?? '…';
          else delete next[payload.userId];
          return next;
        });
      }
    );

    socket.on('message', (payload: { message: Message }) => {
      const { message } = payload;
      setMessagesByChat((prev) => {
        const list = prev[message.chatId] ?? [];
        if (list.some((m) => m.id === message.id)) return prev;
        return {
          ...prev,
          [message.chatId]: [...list, message],
        };
      });

      if (message.chatId === activeChatIdRef.current) {
        socket.emit('mark_read', message.chatId);
      }

      const fromOther = message.senderId !== user.id;
      const viewingThisChat =
        message.chatId === activeChatIdRef.current && !document.hidden;
      if (fromOther && !viewingThisChat) {
        playIncomingMessageSound();
        if (
          typeof Notification !== 'undefined' &&
          Notification.permission === 'granted'
        ) {
          const c =
            chatsRef.current.find((x) => x.id === message.chatId) ?? null;
          const title =
            c?.displayName ??
            (c?.type === 'group' ? c.name : c?.name) ??
            'Silentix';
          new Notification(title, {
            body: notificationBody(message),
            silent: true,
            tag: `chat-${message.chatId}`,
          });
        }
      }
    });

    socket.on('chat_updated', (payload: { chat: Chat }) => {
      setChats((prev) => {
        const idx = prev.findIndex((c) => c.id === payload.chat.id);
        if (idx === -1) return [...prev, payload.chat];
        const next = [...prev];
        next[idx] = { ...next[idx], ...payload.chat };
        return next;
      });
    });

    socket.on('message_deleted', (payload: { chatId: string; messageId: string }) => {
      setMessagesByChat((prev) => {
        const list = prev[payload.chatId];
        if (!list) return prev;
        return {
          ...prev,
          [payload.chatId]: list.map((m) =>
            m.id === payload.messageId ? { ...m, deleted: true } : m
          ),
        };
      });
    });

    return () => {
      socket.disconnect();
      socketRef.current = null;
    };
  }, [user.id]);

  const selectChat = useCallback(
    async (id: string | null) => {
      setActiveChatId(id);
      setTypingNames({});
      if (!id) return;
      const socket = socketRef.current;
      socket?.emit('join_chat', id);

      if (!messagesByChat[id]) {
        try {
          const { messages: list } = await api.fetchMessages(id);
          setMessagesByChat((prev) => ({ ...prev, [id]: list }));
        } catch {
          /* noop */
        }
      }
      socket?.emit('mark_read', id);
      setChats((prev) =>
        prev.map((c) =>
          c.id === id ? { ...c, unread: { ...c.unread, [user.id]: 0 } } : c
        )
      );
    },
    [messagesByChat, user.id]
  );

  const sendPayload = useCallback(
    (p: SendPayload) => {
      if (!activeChatId) return;
      const t = (p.text ?? '').trim();
      if (!t && !p.imageUrl && !p.media) return;
      socketRef.current?.emit('send_message', {
        chatId: activeChatId,
        text: t,
        imageUrl: p.imageUrl,
        media: p.media,
      });
    },
    [activeChatId]
  );

  const deleteMessage = useCallback(
    (messageId: string) => {
      if (!activeChatId) return;
      socketRef.current?.emit('delete_message', {
        chatId: activeChatId,
        messageId,
      });
    },
    [activeChatId]
  );

  const notifyTyping = useCallback(
    (isTyping: boolean) => {
      if (!activeChatId) return;
      socketRef.current?.emit('typing', {
        chatId: activeChatId,
        isTyping,
      });
      if (typingTimerRef.current) clearTimeout(typingTimerRef.current);
      if (isTyping) {
        typingTimerRef.current = setTimeout(() => {
          socketRef.current?.emit('typing', {
            chatId: activeChatId,
            isTyping: false,
          });
        }, 2000);
      }
    },
    [activeChatId]
  );

  const createDirect = useCallback(
    async (username: string) => {
      const { chat } = await api.createDirectChat(username);
      await refreshChats();
      await selectChat(chat.id);
    },
    [refreshChats, selectChat]
  );

  const createGroup = useCallback(
    async (name: string, members: string[]) => {
      const { chat } = await api.createGroupChat(name, members);
      await refreshChats();
      await selectChat(chat.id);
    },
    [refreshChats, selectChat]
  );

  const value = useMemo(
    () => ({
      chats,
      activeChat,
      messages,
      onlineUserIds,
      typingNames,
      chatSearch,
      setChatSearch,
      selectChat,
      sendPayload,
      deleteMessage,
      notifyTyping,
      refreshChats,
      createDirect,
      createGroup,
      socketConnected,
    }),
    [
      chats,
      activeChat,
      messages,
      onlineUserIds,
      typingNames,
      chatSearch,
      selectChat,
      sendPayload,
      deleteMessage,
      notifyTyping,
      refreshChats,
      createDirect,
      createGroup,
      socketConnected,
    ]
  );

  return (
    <MessengerContext.Provider value={value}>
      {children}
    </MessengerContext.Provider>
  );
}

export function useMessenger(): MessengerContextValue {
  const ctx = useContext(MessengerContext);
  if (!ctx) throw new Error('useMessenger outside MessengerProvider');
  return ctx;
}
