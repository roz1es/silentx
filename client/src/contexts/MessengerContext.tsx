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
import { useAuth } from '@/contexts/AuthContext';
import {
  decryptMessage,
  decryptMessages,
  encryptDirectText,
  initializeE2eeForUser,
  isE2eeKeyRestoreRequiredError,
  isDirectTextEncryptionAvailable,
} from '@/lib/e2ee';

export type SendPayload = {
  text?: string;
  imageUrl?: string;
  media?: MessageMedia;
  replyToMessageId?: string;
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
  replyTarget: Message | null;
  setReplyTarget: (message: Message | null) => void;
  clearReply: () => void;
  editTarget: Message | null;
  setEditTarget: (message: Message | null) => void;
  clearEdit: () => void;
  chatSearch: string;
  setChatSearch: (q: string) => void;
  messageSearch: string;
  setMessageSearch: (q: string) => void;
  selectChat: (id: string | null) => void;
  sendPayload: (p: SendPayload) => Promise<void>;
  deleteMessage: (messageId: string) => void;
  editMessage: (messageId: string, text: string) => Promise<void>;
  reactToMessage: (messageId: string, emoji: string) => void;
  forwardMessages: (messageIds: string[], targetChatId: string) => void;
  patchChat: (chatId: string, patch: api.ChatProfilePatch) => Promise<void>;
  addChatMembers: (chatId: string, memberIds: string[]) => Promise<void>;
  notifyTyping: (isTyping: boolean) => void;
  refreshChats: () => Promise<void>;
  createDirect: (target: {
    username?: string;
    userId?: string;
  }) => Promise<void>;
  openSavedChat: () => Promise<void>;
  createGroup: (name: string, memberIds: string[]) => Promise<void>;
  createChannel: (name: string, subscriberIds: string[]) => Promise<void>;
  deleteChat: (chatId: string) => Promise<void>;
  setMuted: (chatId: string, muted: boolean) => Promise<void>;
  setPinnedTop: (chatId: string, pinned: boolean) => Promise<void>;
  pinMessage: (messageId: string | null) => Promise<void>;
  clearChat: (chatId: string) => Promise<void>;
  getSocket: () => Socket | null;
  socketConnected: boolean;
  textEncryptionStatus: 'none' | 'checking' | 'protected' | 'waiting';
  e2eeRecoveryRequired: boolean;
  restoreE2ee: (password: string) => Promise<void>;
  resetE2ee: (password: string) => Promise<void>;
};

const MessengerContext = createContext<MessengerContextValue | null>(null);

// Пока desktop/mobile клиенты не поддерживают E2EE-ключи веб-версии,
// новые текстовые сообщения отправляем открытым текстом, чтобы все приложения
// BrenksChat показывали одинаковое содержимое вместо заглушки "Сообщение".
const directTextE2eeEnabled = false;

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

function visibleMessages(list: Message[]): Message[] {
  return list.filter((m) => !m.deleted);
}

function hasRecoveringEncryptedMessages(list: Message[]): boolean {
  return list.some(
    (message) =>
      Boolean(message.encryptedText) && message.encryptionState === 'recovering'
  );
}

function hasPendingEncryptedMessages(list: Message[]): boolean {
  return list.some(
    (message) =>
      Boolean(message.encryptedText) && message.encryptionState === 'pending'
  );
}

export function MessengerProvider({ children }: { children: ReactNode }) {
  const { user, restoreE2eeKey, resetE2eeKey } = useAuth() as {
    user: User;
    restoreE2eeKey: (password: string) => Promise<void>;
    resetE2eeKey: (password: string) => Promise<void>;
  };
  const [chats, setChats] = useState<Chat[]>([]);
  const [activeChatId, setActiveChatId] = useState<string | null>(null);
  const [messagesByChat, setMessagesByChat] = useState<Record<string, Message[]>>(
    {}
  );
  const [onlineUserIds, setOnlineUserIds] = useState<string[]>([]);
  const [typingNames, setTypingNames] = useState<Record<string, string>>({});
  const [chatSearch, setChatSearch] = useState('');
  const [messageSearch, setMessageSearch] = useState('');
  const [replyTarget, setReplyTarget] = useState<Message | null>(null);
  const [editTarget, setEditTarget] = useState<Message | null>(null);
  const [socketConnected, setSocketConnected] = useState(false);
  const [e2eeReadyVersion, setE2eeReadyVersion] = useState(0);
  const [e2eeRecoveryRequired, setE2eeRecoveryRequired] = useState(false);
  const [textEncryptionStatus, setTextEncryptionStatus] = useState<
    'none' | 'checking' | 'protected' | 'waiting'
  >('none');

  const socketRef = useRef<Socket | null>(null);
  const e2eeReadyPromiseRef = useRef<Promise<void> | null>(null);
  const activeChatIdRef = useRef<string | null>(null);
  const messagesByChatRef = useRef<Record<string, Message[]>>({});
  const chatsRef = useRef<Chat[]>([]);
  const typingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const decryptRetryTimerRef = useRef<ReturnType<typeof setTimeout> | null>(
    null
  );
  const decryptRetryCountRef = useRef(0);

  useEffect(() => {
    activeChatIdRef.current = activeChatId;
  }, [activeChatId]);

  useEffect(() => {
    messagesByChatRef.current = messagesByChat;
  }, [messagesByChat]);

  useEffect(() => {
    chatsRef.current = chats;
  }, [chats]);

  const ensureE2eeReady = useCallback(async () => {
    if (!e2eeReadyPromiseRef.current) {
      e2eeReadyPromiseRef.current = initializeE2eeForUser(user.id)
        .then(() => {
          setE2eeRecoveryRequired(false);
        })
        .catch((error) => {
          e2eeReadyPromiseRef.current = null;
          if (isE2eeKeyRestoreRequiredError(error)) {
            setE2eeRecoveryRequired(true);
          }
          console.warn('[e2ee] не удалось подготовить ключ устройства', error);
          throw error;
        });
    }
    return e2eeReadyPromiseRef.current;
  }, [user.id]);

  const activeChat = useMemo(
    () => chats.find((c) => c.id === activeChatId) ?? null,
    [chats, activeChatId]
  );

  useEffect(() => {
    let cancelled = false;
    if (!activeChat || activeChat.type !== 'direct') {
      setTextEncryptionStatus('none');
      return;
    }
    setTextEncryptionStatus('checking');
    isDirectTextEncryptionAvailable(activeChat.id, user.id)
      .then((available) => {
        if (!cancelled) {
          setTextEncryptionStatus(available ? 'protected' : 'waiting');
        }
      })
      .catch(() => {
        if (!cancelled) setTextEncryptionStatus('waiting');
      });
    return () => {
      cancelled = true;
    };
  }, [activeChat, user.id]);

  const messages = useMemo(
    () => (activeChatId ? visibleMessages(messagesByChat[activeChatId] ?? []) : []),
    [activeChatId, messagesByChat]
  );

  const displayMessages = useMemo(() => {
    const q = messageSearch.trim().toLowerCase();
    if (!q) return messages;
    return messages.filter((m) => {
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

  const decryptLoadedMessages = useCallback(
    async (source: Record<string, Message[]> = messagesByChatRef.current) => {
      const entries = Object.entries(source).filter(([, list]) =>
        list.some(
          (message) =>
            message.encryptedText && message.encryptionState !== 'encrypted'
        )
      );
      if (entries.length === 0) {
        setE2eeRecoveryRequired(false);
        return;
      }
      const resolved = await Promise.all(
        entries.map(async ([chatId, list]) => {
          const decrypted = await decryptMessages(list, user.id);
          return [chatId, visibleMessages(decrypted)] as const;
        })
      );
      setE2eeRecoveryRequired(
        resolved.some(([, decrypted]) =>
          hasRecoveringEncryptedMessages(decrypted)
        )
      );
      setMessagesByChat((prev) => {
        const next = { ...prev };
        for (const [chatId, decrypted] of resolved) {
          const byId = new Map(
            decrypted.map((message) => [message.id, message])
          );
          next[chatId] = (prev[chatId] ?? []).map(
            (message) => byId.get(message.id) ?? message
          );
        }
        return next;
      });
    },
    [user.id]
  );

  useEffect(() => {
    refreshChats().catch(() => {});
  }, [refreshChats]);

  useEffect(() => {
    let cancelled = false;
    e2eeReadyPromiseRef.current = null;
    ensureE2eeReady()
      .then(() => {
        if (!cancelled) setE2eeReadyVersion((value) => value + 1);
      })
      .catch(() => {
        /* Ошибка уже выведена в ensureE2eeReady. */
      });
    return () => {
      cancelled = true;
    };
  }, [ensureE2eeReady]);

  useEffect(() => {
    if (!e2eeReadyVersion) return;
    let cancelled = false;
    decryptLoadedMessages()
      .then(() => {
        if (cancelled) return;
      })
      .catch(() => {
        /* При ошибке сообщения останутся в текущем состоянии. */
      });
    return () => {
      cancelled = true;
    };
  }, [decryptLoadedMessages, e2eeReadyVersion]);

  useEffect(() => {
    if (!socketConnected) return;
    if (chats.length > 0) joinAllChats(chats);
    void decryptLoadedMessages();
  }, [socketConnected, chats, joinAllChats, decryptLoadedMessages]);

  useEffect(() => {
    const pending = Object.values(messagesByChat).some((list) =>
      hasPendingEncryptedMessages(list)
    );
    if (!pending) {
      decryptRetryCountRef.current = 0;
      if (decryptRetryTimerRef.current) {
        clearTimeout(decryptRetryTimerRef.current);
        decryptRetryTimerRef.current = null;
      }
      return;
    }
    decryptRetryCountRef.current += 1;
    const delay = Math.min(10_000, 1_500 + decryptRetryCountRef.current * 900);
    decryptRetryTimerRef.current = setTimeout(() => {
      decryptRetryTimerRef.current = null;
      void decryptLoadedMessages();
    }, delay);
    return () => {
      if (decryptRetryTimerRef.current) {
        clearTimeout(decryptRetryTimerRef.current);
        decryptRetryTimerRef.current = null;
      }
    };
  }, [decryptLoadedMessages, messagesByChat]);

  useEffect(() => {
    const retryVisibleMessages = () => {
      if (!document.hidden) void decryptLoadedMessages();
    };
    window.addEventListener('focus', retryVisibleMessages);
    document.addEventListener('visibilitychange', retryVisibleMessages);
    return () => {
      window.removeEventListener('focus', retryVisibleMessages);
      document.removeEventListener('visibilitychange', retryVisibleMessages);
    };
  }, [decryptLoadedMessages]);

  useEffect(() => {
    /** Base URL для API. Если задан в env — используем его, иначе относительный путь */
    const socketBaseUrl = import.meta.env.VITE_API_URL || undefined;

    const socket = io(socketBaseUrl, {
      path: '/socket.io',
      transports: ['websocket', 'polling'],
      autoConnect: true,
      withCredentials: true,
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

    socket.on('message', async (payload: { message: Message }) => {
      await ensureE2eeReady().catch(() => undefined);
      const message = await decryptMessage(payload.message, user.id);
      if (message.encryptionState === 'recovering') {
        setE2eeRecoveryRequired(true);
      }
      if (message.deleted) return;
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
              'БренксЧат';
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
          [payload.chatId]: list.filter((m) => m.id !== payload.messageId),
        };
      });
      setReplyTarget((cur) =>
        cur?.id === payload.messageId || cur?.replyToMessageId === payload.messageId
          ? null
          : cur
      );
      setEditTarget((cur) => (cur?.id === payload.messageId ? null : cur));
    });

    socket.on('message_edited', async (payload: { message: Message }) => {
      await ensureE2eeReady().catch(() => undefined);
      const message = await decryptMessage(payload.message, user.id);
      if (message.encryptionState === 'recovering') {
        setE2eeRecoveryRequired(true);
      }
      if (message.deleted) return;
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
  }, [ensureE2eeReady, user.id]);

  const selectChat = useCallback(
    async (id: string | null) => {
      setActiveChatId(id);
      setTypingNames({});
      setMessageSearch('');
      setReplyTarget(null);
      setEditTarget(null);
      if (!id) return;
      const socket = socketRef.current;
      socket?.emit('join_chat', id);

      if (!messagesByChat[id]) {
        try {
          await ensureE2eeReady().catch(() => undefined);
          const { messages: list } = await api.fetchMessages(id);
          const decrypted = await decryptMessages(list, user.id);
          if (hasRecoveringEncryptedMessages(decrypted)) {
            setE2eeRecoveryRequired(true);
          }
          setMessagesByChat((prev) => ({
            ...prev,
            [id]: visibleMessages(decrypted),
          }));
        } catch {
          /* noop */
        }
      } else if (
        messagesByChat[id].some(
          (message) =>
            message.encryptedText && message.encryptionState !== 'encrypted'
        )
      ) {
        void ensureE2eeReady()
          .catch(() => undefined)
          .then(() => decryptLoadedMessages({ [id]: messagesByChat[id] }))
          .catch(() => undefined);
      }
      socket?.emit('mark_read', id);
      setChats((prev) =>
        prev.map((c) =>
          c.id === id ? { ...c, unread: { ...c.unread, [user.id]: 0 } } : c
        )
      );
    },
    [ensureE2eeReady, messagesByChat, user.id]
  );

  const clearReply = useCallback(() => {
    setReplyTarget(null);
  }, []);

  const clearEdit = useCallback(() => {
    setEditTarget(null);
  }, []);

  const sendPayload = useCallback(
    async (p: SendPayload) => {
      if (!activeChatId || !activeChat) return;
      const t = (p.text ?? '').trim();
      if (!t && !p.imageUrl && !p.media) return;
      const encryptedText =
        directTextE2eeEnabled && activeChat.type === 'direct' && t
          ? await encryptDirectText(activeChatId, user.id, t)
          : undefined;
      if (directTextE2eeEnabled && activeChat.type === 'direct' && t) {
        setTextEncryptionStatus(
          encryptedText ? 'protected' : 'waiting'
        );
      } else if (t) {
        setTextEncryptionStatus('none');
      }
      socketRef.current?.emit('send_message', {
        chatId: activeChatId,
        text: encryptedText ? '' : t,
        encryptedText,
        imageUrl: p.imageUrl,
        media: p.media,
        replyToMessageId: p.replyToMessageId,
      });
    },
    [activeChat, activeChatId, user.id]
  );

  const reactToMessage = useCallback(
    (messageId: string, emoji: string) => {
      if (!activeChatId) return;
      socketRef.current?.emit('toggle_reaction', {
        chatId: activeChatId,
        messageId,
        emoji,
      });
    },
    [activeChatId]
  );

  const forwardMessages = useCallback(
    (messageIds: string[], targetChatId: string) => {
      if (!activeChatId || !targetChatId || messageIds.length === 0) return;
      socketRef.current?.emit('forward_messages', {
        sourceChatId: activeChatId,
        targetChatId,
        messageIds,
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
          [activeChatId]: list.filter((m) => m.id !== messageId),
        };
      });
      setReplyTarget((cur) =>
        cur?.id === messageId || cur?.replyToMessageId === messageId ? null : cur
      );
      socketRef.current?.emit('delete_message', {
        chatId: activeChatId,
        messageId,
      });
    },
    [activeChatId]
  );

  const editMessage = useCallback(
    async (messageId: string, text: string) => {
      if (!activeChatId || !activeChat) return;
      const t = text.trim();
      if (!t) return;
      const encryptedText =
        directTextE2eeEnabled && activeChat.type === 'direct'
          ? await encryptDirectText(activeChatId, user.id, t)
          : undefined;
      if (directTextE2eeEnabled && activeChat.type === 'direct') {
        setTextEncryptionStatus(encryptedText ? 'protected' : 'waiting');
      } else {
        setTextEncryptionStatus('none');
      }
      setMessagesByChat((prev) => {
        const list = prev[activeChatId];
        if (!list) return prev;
        return {
          ...prev,
          [activeChatId]: list.map((m) =>
            m.id === messageId
              ? {
                  ...m,
                  text: t,
                  encryptedText: encryptedText ?? m.encryptedText,
                  encryptionState: encryptedText
                    ? ('encrypted' as const)
                    : m.encryptionState,
                  editedAt: Date.now(),
                }
              : m
          ),
        };
      });
      socketRef.current?.emit('edit_message', {
        chatId: activeChatId,
        messageId,
        text: encryptedText ? '' : t,
        encryptedText,
      });
    },
    [activeChat, activeChatId, user.id]
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

  const openSavedChat = useCallback(async () => {
    const { chat } = await api.createSavedChat();
    await refreshChats();
    await selectChat(chat.id);
  }, [refreshChats, selectChat]);

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

  const restoreE2ee = useCallback(
    async (password: string) => {
      await restoreE2eeKey(password);
      e2eeReadyPromiseRef.current = null;
      await ensureE2eeReady();
      await decryptLoadedMessages();
      setE2eeReadyVersion((value) => value + 1);
    },
    [decryptLoadedMessages, ensureE2eeReady, restoreE2eeKey]
  );

  const resetE2ee = useCallback(
    async (password: string) => {
      await resetE2eeKey(password);
      e2eeReadyPromiseRef.current = null;
      await ensureE2eeReady();
      await decryptLoadedMessages();
      setE2eeReadyVersion((value) => value + 1);
    },
    [decryptLoadedMessages, ensureE2eeReady, resetE2eeKey]
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
      replyTarget,
      setReplyTarget,
      clearReply,
      editTarget,
      setEditTarget,
      clearEdit,
      selectChat,
      sendPayload,
      deleteMessage,
      editMessage,
      reactToMessage,
      forwardMessages,
      patchChat,
      addChatMembers,
      notifyTyping,
      refreshChats,
      createDirect,
      openSavedChat,
      createGroup,
      createChannel,
      deleteChat,
      setMuted,
      setPinnedTop,
      pinMessage,
      clearChat,
      getSocket,
      socketConnected,
      textEncryptionStatus,
      e2eeRecoveryRequired,
      restoreE2ee,
      resetE2ee,
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
      replyTarget,
      clearReply,
      editTarget,
      clearEdit,
      selectChat,
      sendPayload,
      deleteMessage,
      editMessage,
      reactToMessage,
      forwardMessages,
      patchChat,
      addChatMembers,
      notifyTyping,
      refreshChats,
      createDirect,
      openSavedChat,
      createGroup,
      createChannel,
      deleteChat,
      setMuted,
      setPinnedTop,
      pinMessage,
      clearChat,
      getSocket,
      socketConnected,
      textEncryptionStatus,
      e2eeRecoveryRequired,
      restoreE2ee,
      resetE2ee,
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
