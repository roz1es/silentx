import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import type { Chat } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { useCall } from '@/contexts/CallContext';
import { useMessenger } from '@/contexts/MessengerContext';
import { UserAvatar } from '@/components/UserAvatar';
import {
  IconMoreVertical,
  IconLock,
  IconPalette,
  IconPhone,
  IconSearch,
  IconVideoCam,
} from '@/components/icons';
import { useChatWallpaper } from '@/contexts/ChatWallpaperContext';
import { CHAT_WALLPAPER_PRESETS } from '@/lib/chatWallpaper';
import { ruSubscribers } from '@/lib/pluralRu';
import { chatParticipantLabel } from '@/lib/userDisplay';

function titleFor(chat: Chat | null, selfId: string): string {
  if (!chat) return 'БренксЧат';
  if (chat.displayName) return chat.displayName;
  if (chat.type === 'group' || chat.type === 'channel') return chat.name;
  const other = chat.participants?.find((p) => p.id !== selfId);
  if (other) return chatParticipantLabel(other);
  return chat.name || 'Чат';
}

function avatarForChat(
  chat: Chat | null,
  selfId: string
): { username: string; avatarUrl?: string } | null {
  if (!chat) return null;
  const parts = chat.participants ?? [];
  if (chat.type === 'group' || chat.type === 'channel') {
    return { username: chat.name, avatarUrl: chat.avatarUrl };
  }
  const other = parts.find((p) => p.id !== selfId);
  if (other)
    return {
      username: chatParticipantLabel(other),
      avatarUrl: other.avatarUrl,
    };
  return { username: titleFor(chat, selfId), avatarUrl: undefined };
}

function deleteChatConfirmText(chat: Chat, selfId: string): string {
  if (chat.type === 'direct') {
    return 'Удалить чат для вас и собеседника? Вся переписка будет удалена.';
  }
  if (chat.type === 'channel') {
    if (chat.channelOwnerId === selfId) {
      return 'Удалить канал для всех подписчиков?';
    }
    return 'Отписаться от канала?';
  }
  return 'Выйти из группы? Вы перестанете получать сообщения.';
}

function deleteChatMenuLabel(chat: Chat, selfId: string): string {
  if (chat.type === 'direct') return 'Удалить чат';
  if (chat.type === 'channel') {
    return chat.channelOwnerId === selfId ? 'Удалить канал' : 'Отписаться';
  }
  return 'Выйти из группы';
}

type Props = {
  onGroupInfo?: () => void;
  onPeerProfile?: () => void;
};

export function ChatHeader({ onGroupInfo, onPeerProfile }: Props) {
  const { user } = useAuth();
  const {
    activeChat,
    onlineUserIds,
    typingNames,
    messageSearch,
    setMessageSearch,
    setMuted,
    setPinnedTop,
    clearChat,
    deleteChat,
    textEncryptionStatus,
  } = useMessenger();
  const { startCall } = useCall();
  const { wallpaperId, setWallpaperId } = useChatWallpaper();
  const [menuOpen, setMenuOpen] = useState(false);
  const [wallpaperOpen, setWallpaperOpen] = useState(false);
  const [searchOpen, setSearchOpen] = useState(false);
  const [menuPos, setMenuPos] = useState({ top: 0, right: 0 });
  const menuButtonRef = useRef<HTMLButtonElement>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    if (!menuOpen || !menuButtonRef.current) return;
    const r = menuButtonRef.current.getBoundingClientRect();
    setMenuPos({
      top: r.bottom + 6,
      right: window.innerWidth - r.right,
    });
  }, [menuOpen]);

  useEffect(() => {
    if (!menuOpen) return;
    const onDoc = (e: MouseEvent) => {
      const t = e.target as Node;
      if (
        menuButtonRef.current?.contains(t) ||
        dropdownRef.current?.contains(t)
      ) {
        return;
      }
      setMenuOpen(false);
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, [menuOpen]);

  const heading = useMemo(
    () => titleFor(activeChat, user?.id ?? ''),
    [activeChat, user?.id]
  );

  const av = useMemo(
    () => avatarForChat(activeChat, user?.id ?? ''),
    [activeChat, user?.id]
  );

  const otherOnline = useMemo(() => {
    if (!activeChat) return false;
    if (activeChat.type === 'group' || activeChat.type === 'channel') {
      const inChat = activeChat.participantIds ?? [];
      return inChat.some((id) => id !== user?.id && onlineUserIds.includes(id));
    }
    const other = activeChat.participantIds.find((id) => id !== user?.id);
    return other ? onlineUserIds.includes(other) : false;
  }, [activeChat, onlineUserIds, user?.id]);

  const otherUserId = useMemo(() => {
    if (!activeChat || !user) return null;
    if (activeChat.type !== 'direct') return null;
    return activeChat.participantIds.find((id) => id !== user.id) ?? null;
  }, [activeChat, user]);

  const typingEntries = Object.entries(typingNames);
  const typingLabel = useMemo(() => {
    if (typingEntries.length === 1) {
      return `${typingEntries[0][1]} печатает`;
    }
    if (typingEntries.length > 1) {
      return `${typingEntries.map(([, name]) => name).join(', ')} печатают`;
    }
    return '';
  }, [typingNames]);

  const status = useMemo(() => {
    if (!activeChat) return '';
    if (activeChat.type === 'channel') {
      const n = activeChat.participantIds?.length ?? 0;
      return ruSubscribers(n);
    }
    if (activeChat.type === 'group') {
      const n = activeChat.participantIds?.length ?? 0;
      return `${n} участников`;
    }
    if (otherOnline) return 'в сети';
    return 'не в сети';
  }, [activeChat, otherOnline]);

  if (!user) return null;

  const showGroupStyle =
    activeChat?.type === 'group' || activeChat?.type === 'channel';

  const titleEl =
    showGroupStyle && onGroupInfo ? (
      <button
        type="button"
        onClick={onGroupInfo}
        className="truncate text-left text-base font-semibold text-slate-900 hover:underline dark:text-slate-100"
      >
        {heading}
      </button>
    ) : (
      <h1 className="truncate text-base font-semibold text-slate-900 dark:text-slate-100">
        {heading}
      </h1>
    );

  const groupAvatar =
    showGroupStyle && av ? (
      <UserAvatar
        username={av.username}
        avatarUrl={av.avatarUrl}
        size="sm"
        className="shrink-0"
      />
    ) : showGroupStyle ? (
      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-tg-accent text-xs font-bold text-white shadow-md sm:h-9 sm:w-9 sm:text-sm">
        {heading.slice(0, 1).toUpperCase()}
      </div>
    ) : null;

  const directAvatar =
    !showGroupStyle && activeChat?.type === 'direct' && onPeerProfile ? (
      <button
        type="button"
        onClick={onPeerProfile}
        title="Профиль"
        className="shrink-0 rounded-full focus:outline-none focus:ring-2 focus:ring-tg-accent/50"
      >
        {av ? (
          <UserAvatar
            username={av.username}
            avatarUrl={av.avatarUrl}
            size="sm"
          />
        ) : null}
      </button>
    ) : !showGroupStyle && activeChat?.type === 'direct' && av ? (
      <UserAvatar
        username={av.username}
        avatarUrl={av.avatarUrl}
        size="sm"
        className="shrink-0"
      />
    ) : null;

  const closeMenu = () => setMenuOpen(false);

  const menuPortal =
    menuOpen && activeChat
      ? createPortal(
          <div
            ref={dropdownRef}
            className="fixed z-[10000] min-w-[220px] rounded-xl border border-white/70 bg-white/90 py-1 shadow-2xl backdrop-blur-xl dark:border-white/10 dark:bg-zinc-800/90 dark:shadow-black/30"
            style={{ top: menuPos.top, right: menuPos.right }}
            role="menu"
          >
            <button
              type="button"
              className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm hover:bg-tg-hover"
              onClick={() => {
                setWallpaperOpen(true);
                closeMenu();
              }}
            >
              <IconPalette className="h-4 w-4 shrink-0 opacity-70" />
              Фон чатов
            </button>
            <button
              type="button"
              className="flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm hover:bg-tg-hover"
              onClick={() => {
                setSearchOpen(true);
                closeMenu();
              }}
            >
              <IconSearch className="h-4 w-4 shrink-0 opacity-70" />
              Поиск в чате
            </button>
            <button
              type="button"
              className="block w-full px-4 py-2.5 text-left text-sm hover:bg-tg-hover"
              onClick={() => {
                void setMuted(activeChat.id, !activeChat.muted);
                closeMenu();
              }}
            >
              {activeChat.muted ? 'Включить уведомления' : 'Без звука'}
            </button>
            <button
              type="button"
              className="block w-full px-4 py-2.5 text-left text-sm hover:bg-tg-hover"
              onClick={() => {
                void setPinnedTop(activeChat.id, !activeChat.pinnedToTop);
                closeMenu();
              }}
            >
              {activeChat.pinnedToTop ? 'Открепить чат' : 'Закрепить чат'}
            </button>
            {!(
              activeChat.type === 'channel' &&
              activeChat.channelOwnerId !== user.id
            ) ? (
              <button
                type="button"
                className="block w-full px-4 py-2.5 text-left text-sm text-red-600 hover:bg-tg-hover dark:text-red-400"
                onClick={() => {
                  closeMenu();
                  if (
                    window.confirm(
                      'Удалить все сообщения в чате у всех участников?'
                    )
                  ) {
                    void clearChat(activeChat.id);
                  }
                }}
              >
                Очистить историю
              </button>
            ) : null}
            <button
              type="button"
              className="block w-full px-4 py-2.5 text-left text-sm text-red-600 hover:bg-tg-hover dark:text-red-400"
              onClick={() => {
                closeMenu();
                if (window.confirm(deleteChatConfirmText(activeChat, user.id))) {
                  void deleteChat(activeChat.id);
                }
              }}
            >
              {deleteChatMenuLabel(activeChat, user.id)}
            </button>
          </div>,
          document.body
        )
      : null;

  return (
    <div className="relative z-20 shrink-0 border-b border-white/70 bg-white/75 shadow-[0_8px_26px_rgba(15,23,42,0.06)] backdrop-blur-2xl dark:border-zinc-600/40 dark:bg-zinc-800/95 dark:shadow-none">
      <header className="flex h-12 items-center gap-2 px-2 md:h-14 md:gap-3 md:px-4">
        {showGroupStyle ? groupAvatar : directAvatar}
        <div className="flex min-w-0 flex-1 flex-col justify-center">
          <div className="flex min-w-0 items-center gap-1.5">
            {titleEl}
            {textEncryptionStatus === 'protected' ? (
              <span
                className="shrink-0 text-emerald-600 dark:text-emerald-400"
                title="Новые текстовые сообщения защищены сквозным шифрованием"
              >
                <IconLock className="h-3.5 w-3.5" />
              </span>
            ) : null}
          </div>
          {activeChat ? (
            <p
              className={`truncate text-[10px] sm:text-xs ${
                typingLabel ? 'text-sky-600 dark:text-sky-300' : 'text-tg-muted'
              }`}
            >
              {typingLabel ? (
                <span className="typing-status" aria-label={typingLabel}>
                  <span className="truncate">{typingLabel}</span>
                  <span className="typing-dots" aria-hidden>
                    <span />
                    <span />
                    <span />
                  </span>
                </span>
              ) : (
                status
              )}
            </p>
          ) : null}
        </div>
        {activeChat && otherUserId ? (
          <div className="flex shrink-0 items-center gap-0.5">
            <button
              type="button"
              title="Аудиозвонок"
              onClick={() => void startCall(otherUserId, 'audio')}
              className="flex h-9 w-9 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover hover:text-slate-800 dark:hover:text-slate-100"
            >
              <IconPhone className="h-[1.15rem] w-[1.15rem]" />
            </button>
            <button
              type="button"
              title="Видеозвонок"
              onClick={() => void startCall(otherUserId, 'video')}
              className="flex h-9 w-9 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover hover:text-slate-800 dark:hover:text-slate-100"
            >
              <IconVideoCam className="h-[1.15rem] w-[1.15rem]" />
            </button>
          </div>
        ) : null}
        {activeChat ? (
          <div className="relative shrink-0">
            <button
              ref={menuButtonRef}
              type="button"
              title="Меню чата"
              onClick={() => setMenuOpen((o) => !o)}
              className="flex h-9 w-9 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover"
            >
              <IconMoreVertical className="h-5 w-5" />
            </button>
          </div>
        ) : null}
        {menuPortal}
        <div
          className={`relative h-2.5 w-2.5 shrink-0 ${
            otherOnline ? 'pulse-online' : ''
          }`}
          title={
            typingEntries.length ? 'Печатает' : otherOnline ? 'Онлайн' : 'Оффлайн'
          }
        >
          <div
            className={`h-2.5 w-2.5 shrink-0 rounded-full ${
              typingEntries.length > 0
                ? 'typing-presence-dot bg-sky-400'
                : otherOnline
                  ? 'bg-emerald-500'
                  : 'bg-slate-400'
            }`}
          />
        </div>
      </header>
      {activeChat && searchOpen ? (
        <div className="border-t border-tg-border/80 px-3 py-2 md:px-4">
          <div className="relative mx-auto max-w-3xl">
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-tg-muted">
              <IconSearch className="h-4 w-4" />
            </span>
            <input
              autoFocus
              value={messageSearch}
              onChange={(e) => setMessageSearch(e.target.value)}
              placeholder="Поиск по сообщениям…"
              className="w-full rounded-2xl border border-tg-border bg-white py-2.5 pl-10 pr-24 text-sm shadow-inner outline-none ring-2 ring-transparent transition focus:border-[rgb(var(--tg-accent))] focus:ring-[rgb(var(--tg-accent))]/20 dark:bg-slate-900/50 dark:text-slate-100"
            />
            <button
              type="button"
              onClick={() => {
                setMessageSearch('');
                setSearchOpen(false);
              }}
              className="absolute right-2 top-1/2 -translate-y-1/2 rounded-lg px-2 py-1 text-xs font-medium text-tg-muted hover:bg-tg-hover"
            >
              Закрыть
            </button>
          </div>
        </div>
      ) : null}
      {wallpaperOpen
        ? createPortal(
            <div
              className="fixed inset-0 z-[10001] flex items-end justify-center bg-black/40 p-4 pb-8 backdrop-blur-[2px] sm:items-center sm:pb-4"
              role="dialog"
              aria-modal="true"
              aria-label="Фон чатов"
              onMouseDown={(e) => {
                if (e.target === e.currentTarget) setWallpaperOpen(false);
              }}
            >
              <div className="w-full max-w-sm rounded-2xl border border-white/70 bg-white/95 p-4 shadow-2xl backdrop-blur-xl dark:border-white/10 dark:bg-zinc-800/95 dark:shadow-black/30">
                <h3 className="text-base font-semibold text-slate-900 dark:text-slate-100">
                  Фон чатов
                </h3>
                <p className="mt-1 text-xs text-tg-muted">
                  Как в Telegram — один стиль для области сообщений
                </p>
                <div className="mt-4 grid grid-cols-3 gap-2">
                  {CHAT_WALLPAPER_PRESETS.map((p) => (
                    <button
                      key={p.id}
                      type="button"
                      onClick={() => {
                        setWallpaperId(p.id);
                        setWallpaperOpen(false);
                      }}
                      className={`flex flex-col items-center gap-1.5 rounded-xl border-2 p-2 transition hover:bg-tg-hover ${
                        wallpaperId === p.id
                          ? 'border-slate-400 bg-slate-100/80 dark:border-slate-500 dark:bg-white/5'
                          : 'border-transparent'
                      }`}
                    >
                      <span
                        className={`h-12 w-full overflow-hidden rounded-lg border border-tg-border/50 shadow-inner ${p.previewClass}`}
                      />
                      <span className="text-center text-[10px] font-medium leading-tight text-tg-muted">
                        {p.label}
                      </span>
                    </button>
                  ))}
                </div>
                <button
                  type="button"
                  onClick={() => setWallpaperOpen(false)}
                  className="mt-4 w-full rounded-xl bg-tg-hover py-2.5 text-sm font-medium text-slate-800 dark:text-slate-200"
                >
                  Закрыть
                </button>
              </div>
            </div>,
            document.body
          )
        : null}
    </div>
  );
}
