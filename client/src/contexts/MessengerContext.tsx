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
import { io } from 'socket.io-client';
import type { Socket } from 'socket.io-client';
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
  /** Сообщения активного чата с учётом поиска в чате */
  displayMessages: Message[];
  onlineUserIds: string[];
  /** userId -> username для активного чата */
  typingNames: Record<string, string>;
  chatSearch: string;
  setChatSearch: (q: string) => void;
  messageSearch: string;
  setMessageSearch: (q: string) => void;
  selectChat: (id: string | null) => void;
  sendPayload: (p: SendPayload) => void;
  deleteMessage: (messageId: string) => void;
  editMessage: (messageId: string, text: string) => void;
  patchChat: (chatId: string, patch: api.ChatProfilePatch) => Promise<void>;
  addChatMembers: (chatId: string, memberIds: string[]) => Promise<void>;
  notifyTyping: (isTyping: boolean) => void;
  refreshChats: () => Promise<void>;
  createDirect: (target: {
    username?: string;
    userId?: string;
  }) => Promise<void>;
  createGroup: (name: string, memberIds: string[]) => Promise<void>;
  createChannel: (name: string, subscriberIds: string[]) => Promise<void>;
  deleteChat: (chatId: string) => Promise<void>;
  setMuted: (chatId: string, muted: boolean) => Promise<void>;
  setPinnedTop: (chatId: string, pinned: boolean) => Promise<void>;
  pinMessage: (messageId: string | null) => Promise<void>;
  clearChat: (chatId: string) => Promise<void>;
  getSocket: () => Socket | null;
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
    const play = () => {
      const now = ctx.currentTime;
      
      // Мягкий мелодичный звук "пинг"
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(880, now); // A5
      osc.frequency.setValueAtTime(1109, now + 0.05); // C#6
      osc.frequency.setValueAtTime(1319, now + 0.1); // E6
      gain.gain.setValueAtTime(0, now);
      gain.gain.linearRampToValueAtTime(0.12, now + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.3);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now);
      osc.stop(now + 0.3);
      
      setTimeout(() => {
        try {
          void ctx.close();
        } catch {
          /* noop */
        }
      }, 400);
    };
    if (ctx.state === 'suspended') void ctx.resume().then(play).catch(() => {});
    else play();
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
  const [messageSearch, setMessageSearch] = useState('');
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

  const displayMessages = useMemo(() => {
    const q = messageSearch.trim().toLowerCase();
    if (!q) return messages;
    return messages.filter((m) => {
      if (m.deleted) return false;
      if (m.text.toLowerCase().includes(q)) return true;
      if (
        m.media?.kind === 'file' &&
        m.media.fileName?.toLowerCase().includes(q)
      )
        return true;
      return false;
    });
  }, [messages, messageSearch]);

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
        const c =
          chatsRef.current.find((x) => x.id === message.chatId) ?? null;
        if (!c?.muted) {
          playIncomingMessageSound();
          if (
            typeof Notification !== 'undefined' &&
            Notification.permission === 'granted'
          ) {
            const title =
              c?.displayName ??
              (c?.type === 'group' || c?.type === 'channel'
                ? c.name
                : c?.name) ??
              'SilentX';
            new Notification(title, {
              body: notificationBody(message),
              silent: true,
              tag: `chat-${message.chatId}`,
            });
          }
        }
      }
    });

    socket.on('chat_updated', (payload: { chat: Chat }) => {
      setChats((prev) => {
        const idx = prev.findIndex((c) => c.id === payload.chat.id);
        if (idx === -1) return [...prev, payload.chat];
        const next = [...prev];
        const cur = next[idx];
        const incoming = payload.chat;
        next[idx] = {
          ...cur,
          ...incoming,
          displayName: incoming.displayName ?? cur.displayName,
          participants: incoming.participants ?? cur.participants,
          channelOwnerId:
            incoming.channelOwnerId !== undefined
              ? incoming.channelOwnerId
              : cur.channelOwnerId,
          avatarUrl:
            incoming.avatarUrl === null
              ? undefined
              : incoming.avatarUrl !== undefined
                ? incoming.avatarUrl
                : cur.avatarUrl,
          muted: incoming.muted ?? cur.muted,
          pinnedToTop: incoming.pinnedToTop ?? cur.pinnedToTop,
          pinnedMessageId:
            incoming.pinnedMessageId === null
              ? undefined
              : incoming.pinnedMessageId !== undefined
                ? incoming.pinnedMessageId
                : cur.pinnedMessageId,
        };
        return next;
      });
    });

    socket.on('chat_deleted', (payload: { chatId: string }) => {
      const { chatId } = payload;
      setChats((prev) => prev.filter((c) => c.id !== chatId));
      setMessagesByChat((prev) => {
        if (!(chatId in prev)) return prev;
        const next = { ...prev };
        delete next[chatId];
        return next;
      });
      if (activeChatIdRef.current === chatId) {
        setActiveChatId(null);
      }
    });

    socket.on('messages_cleared', (payload: { chatId: string }) => {
      const { chatId } = payload;
      setMessagesByChat((prev) => ({ ...prev, [chatId]: [] }));
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

    socket.on('message_edited', (payload: { message: Message }) => {
      const { message } = payload;
      setMessagesByChat((prev) => {
        const list = prev[message.chatId];
        if (!list) return prev;
        return {
          ...prev,
          [message.chatId]: list.map((m) =>
            m.id === message.id ? message : m
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
      setMessageSearch('');
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
      setMessagesByChat((prev) => {
        const list = prev[activeChatId];
        if (!list) return prev;
        return {
          ...prev,
          [activeChatId]: list.map((m) =>
            m.id === messageId ? { ...m, deleted: true } : m
          ),
        };
      });
      socketRef.current?.emit('delete_message', {
        chatId: activeChatId,
        messageId,
      });
    },
    [activeChatId]
  );

  const editMessage = useCallback(
    (messageId: string, text: string) => {
      if (!activeChatId) return;
      const t = text.trim();
      if (!t) return;
      setMessagesByChat((prev) => {
        const list = prev[activeChatId];
        if (!list) return prev;
        return {
          ...prev,
          [activeChatId]: list.map((m) =>
            m.id === messageId
              ? { ...m, text: t, editedAt: Date.now() }
              : m
          ),
        };
      });
      socketRef.current?.emit('edit_message', {
        chatId: activeChatId,
        messageId,
        text: t,
      });
    },
    [activeChatId]
  );

  const patchChat = useCallback(async (chatId: string, patch: api.ChatProfilePatch) => {
    const { chat } = await api.patchChat(chatId, patch);
    setChats((prev) => {
      const idx = prev.findIndex((c) => c.id === chat.id);
      if (idx === -1) return [...prev, chat];
      const next = [...prev];
      const cur = next[idx];
      next[idx] = {
        ...cur,
        ...chat,
        participants: chat.participants ?? cur.participants,
      };
      return next;
    });
  }, []);

  const addChatMembers = useCallback(
    async (chatId: string, memberIds: string[]) => {
      const { chat } = await api.addChatMembersApi(chatId, memberIds);
      setChats((prev) => {
        const idx = prev.findIndex((c) => c.id === chat.id);
        if (idx === -1) return [...prev, chat];
        const next = [...prev];
        const cur = next[idx];
        next[idx] = {
          ...cur,
          ...chat,
          participants: chat.participants ?? cur.participants,
        };
        return next;
      });
      joinAllChats([chat]);
    },
    [joinAllChats]
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
    async (target: { username?: string; userId?: string }) => {
      const { chat } = await api.createDirectChat({
        targetUsername: target.username,
        targetUserId: target.userId,
      });
      await refreshChats();
      await selectChat(chat.id);
    },
    [refreshChats, selectChat]
  );

  const createGroup = useCallback(
    async (name: string, memberIds: string[]) => {
      const { chat } = await api.createGroupChat(name, memberIds);
      await refreshChats();
      await selectChat(chat.id);
    },
    [refreshChats, selectChat]
  );

  const createChannel = useCallback(
    async (name: string, subscriberIds: string[]) => {
      const { chat } = await api.createChannelChat(name, subscriberIds);
      await refreshChats();
      await selectChat(chat.id);
    },
    [refreshChats, selectChat]
  );

  const deleteChat = useCallback(
    async (chatId: string) => {
      await api.deleteChat(chatId);
      setChats((prev) => prev.filter((c) => c.id !== chatId));
      setMessagesByChat((prev) => {
        if (!(chatId in prev)) return prev;
        const next = { ...prev };
        delete next[chatId];
        return next;
      });
      if (activeChatIdRef.current === chatId) {
        setActiveChatId(null);
      }
    },
    []
  );

  const setMuted = useCallback(async (chatId: string, muted: boolean) => {
    await api.setChatMuted(chatId, muted);
    setChats((prev) =>
      prev.map((c) => (c.id === chatId ? { ...c, muted } : c))
    );
  }, []);

  const setPinnedTop = useCallback(async (chatId: string, pinned: boolean) => {
    await api.setChatPinnedTop(chatId, pinned);
    setChats((prev) =>
      prev.map((c) => (c.id === chatId ? { ...c, pinnedToTop: pinned } : c))
    );
  }, []);

  const pinMessage = useCallback(
    async (messageId: string | null) => {
      if (!activeChatId) return;
      await api.setPinnedMessage(activeChatId, messageId);
      setChats((prev) =>
        prev.map((c) =>
          c.id === activeChatId
            ? {
                ...c,
                pinnedMessageId:
                  messageId === null ? undefined : messageId,
              }
            : c
        )
      );
    },
    [activeChatId]
  );

  const clearChat = useCallback(
    async (chatId: string) => {
      await api.clearChatMessages(chatId);
      setMessagesByChat((prev) => ({ ...prev, [chatId]: [] }));
    },
    []
  );

  const getSocket = useCallback(() => socketRef.current, []);

  const value = useMemo(
    () => ({
      chats,
      activeChat,
      messages,
      displayMessages,
      onlineUserIds,
      typingNames,
      chatSearch,
      setChatSearch,
      messageSearch,
      setMessageSearch,
      selectChat,
      sendPayload,
      deleteMessage,
      editMessage,
      patchChat,
      addChatMembers,
      notifyTyping,
      refreshChats,
      createDirect,
      createGroup,
      createChannel,
      deleteChat,
      setMuted,
      setPinnedTop,
      pinMessage,
      clearChat,
      getSocket,
      socketConnected,
    }),
    [
      chats,
      activeChat,
      messages,
      displayMessages,
      onlineUserIds,
      typingNames,
      chatSearch,
      messageSearch,
      selectChat,
      sendPayload,
      deleteMessage,
      editMessage,
      patchChat,
      addChatMembers,
      notifyTyping,
      refreshChats,
      createDirect,
      createGroup,
      createChannel,
      deleteChat,
      setMuted,
      setPinnedTop,
      pinMessage,
      clearChat,
      getSocket,
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
