import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { CallProvider } from '@/contexts/CallContext';
import { ChatWallpaperProvider } from '@/contexts/ChatWallpaperContext';
import { MessengerProvider, useMessenger } from '@/contexts/MessengerContext';
import { IconArrowLeft } from '@/components/icons';
import { ChatList } from '@/components/ChatList';
import { ChatWindow } from '@/components/ChatWindow';
import { ChatHeader } from '@/components/ChatHeader';
import { MessageInput } from '@/components/MessageInput';
import { ThemeToggle } from '@/components/ThemeToggle';
import { NewChatModal } from '@/components/NewChatModal';
import { GroupMembersModal } from '@/components/GroupMembersModal';
import { ProfileModal } from '@/components/ProfileModal';
import { PeerProfileModal } from '@/components/PeerProfileModal';
import { UserAvatar } from '@/components/UserAvatar';
import { participantLabel } from '@/lib/userDisplay';

function requestNotify() {
  if (typeof Notification === 'undefined') return;
  if (Notification.permission === 'default') void Notification.requestPermission();
}

function MessengerLayout() {
  const { user, logout } = useAuth();
  const { activeChat, selectChat, socketConnected, onlineUserIds } =
    useMessenger();
  if (!user) return null;
  const [newOpen, setNewOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [groupOpen, setGroupOpen] = useState(false);
  const [mobileShowList, setMobileShowList] = useState(true);
  const [peerProfileId, setPeerProfileId] = useState<string | null>(null);
  const [logoutConfirmOpen, setLogoutConfirmOpen] = useState(false);

  const handleLogout = () => {
    setLogoutConfirmOpen(true);
  };

  const confirmLogout = () => {
    setLogoutConfirmOpen(false);
    logout();
  };

  useEffect(() => {
    requestNotify();
  }, []);

  useEffect(() => {
    if (activeChat) setMobileShowList(false);
  }, [activeChat?.id]);

  const showList = mobileShowList || !activeChat;

  const directPeerChat =
    activeChat && activeChat.type === 'direct' ? activeChat : null;

  return (
    <div className="flex h-[100dvh] w-full flex-col overflow-hidden bg-tg-bg md:flex-row">
      <aside
        className={`relative flex min-h-0 w-full shrink-0 flex-col border-tg-border md:flex md:w-[min(100%,22rem)] md:border-r ${
          showList ? 'flex' : 'hidden md:flex'
        }`}
      >
        <div className="flex h-14 shrink-0 items-center gap-2 border-b border-tg-border bg-tg-panel px-3">
          <button
            type="button"
            onClick={() => setProfileOpen(true)}
            className="flex min-w-0 flex-1 items-center gap-2 rounded-xl text-left transition hover:bg-tg-hover"
            title="Профиль"
          >
            <UserAvatar
              username={participantLabel(user)}
              avatarUrl={user.avatarUrl}
              size="sm"
            />
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                {participantLabel(user)}
              </p>
              <p className="text-[11px] text-tg-muted">
                {socketConnected ? 'SilentX · онлайн' : 'соединение…'}
              </p>
            </div>
          </button>
          <ThemeToggle />
          {user.isAdmin ? (
            <Link
              to="/admin"
              title="Админ-панель"
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-tg-muted transition hover:bg-tg-hover hover:text-slate-800 dark:hover:text-slate-100"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.65"
                strokeLinejoin="round"
                className="h-[1.15rem] w-[1.15rem]"
                aria-hidden
              >
                <path d="M12 3 5 7v5c0 4.5 2.8 8.7 7 10 4.2-1.3 7-5.5 7-10V7l-7-4z" />
              </svg>
            </Link>
          ) : null}
          <button
            type="button"
            onClick={handleLogout}
            title="Выйти"
            aria-label="Выйти из аккаунта"
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-tg-muted transition-all duration-500 ease-out hover:bg-red-500/12 hover:text-red-600 dark:hover:bg-red-500/15 dark:hover:text-red-400"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.65"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="h-[1.15rem] w-[1.15rem]"
              aria-hidden
            >
              <path d="M5 4h9a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z" />
              <path d="M14 12h6M17 9l3 3-3 3" />
              <circle cx="10" cy="12" r="0.9" fill="currentColor" stroke="none" />
            </svg>
          </button>
        </div>
        <div className="min-h-0 min-w-0 flex-1">
          <ChatList />
        </div>
        {/* Кнопка нового чата - только на десктопах */}
        <div className="shrink-0 border-t border-tg-border bg-tg-panel px-3 py-2 max-md:hidden">
          <button
            type="button"
            onClick={() => setNewOpen(true)}
            title="Новый чат"
            aria-label="Новый чат"
            className="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-sky-400 to-blue-600 text-[1.5rem] font-light leading-none text-white shadow-md shadow-sky-500/30 ring-1 ring-black/5 transition-all duration-300 hover:scale-[1.03] hover:shadow-lg hover:shadow-sky-500/35 active:scale-[0.98] dark:from-sky-500 dark:to-blue-700 dark:ring-white/10"
          >
            +
          </button>
        </div>
      </aside>

      {/* Кнопка нового чата - плавающая на мобильных, только на экране списка */}
      {showList && (
        <button
          type="button"
          onClick={() => setNewOpen(true)}
          title="Новый чат"
          aria-label="Новый чат"
          className="fixed bottom-4 right-4 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-sky-400 to-blue-600 text-2xl font-light leading-none text-white shadow-lg shadow-sky-500/40 ring-1 ring-black/5 transition-all duration-300 hover:scale-105 hover:shadow-xl hover:shadow-sky-500/50 active:scale-95 md:hidden dark:from-sky-500 dark:to-blue-700 dark:ring-white/10"
        >
          +
        </button>
      )}

      <section
        className={`flex min-h-0 min-w-0 flex-1 flex-col ${
          !showList ? 'flex' : 'hidden md:flex'
        }`}
      >
        <div className="flex items-center gap-0 bg-tg-panel">
          <button
            type="button"
            className="flex px-2 py-3 text-tg-muted md:hidden"
            aria-label="Назад к списку"
            onClick={() => {
              setMobileShowList(true);
              void selectChat(null);
            }}
          >
            <IconArrowLeft className="h-6 w-6" />
          </button>
          <div className="min-w-0 flex-1">
            <ChatHeader
              onGroupInfo={
                activeChat?.type === 'group' ||
                activeChat?.type === 'channel'
                  ? () => setGroupOpen(true)
                  : undefined
              }
              onPeerProfile={
                directPeerChat
                  ? () => {
                      const other = directPeerChat.participantIds.find(
                        (id) => id !== user.id
                      );
                      if (other) setPeerProfileId(other);
                    }
                  : undefined
              }
            />
          </div>
        </div>
        <ChatWindow onOpenUserProfile={(id) => setPeerProfileId(id)} />
        <MessageInput />
      </section>

      <NewChatModal open={newOpen} onClose={() => setNewOpen(false)} />
      <ProfileModal open={profileOpen} onClose={() => setProfileOpen(false)} />
      <PeerProfileModal
        userId={peerProfileId}
        onClose={() => setPeerProfileId(null)}
      />
      <GroupMembersModal
        open={groupOpen}
        onClose={() => setGroupOpen(false)}
        chat={activeChat}
        onlineUserIds={onlineUserIds}
        selfId={user.id}
        onMemberClick={(id) => setPeerProfileId(id)}
      />

      {/* Подтверждение выхода из аккаунта */}
      {logoutConfirmOpen && (
        <div
          className="fixed inset-0 z-[10000] flex items-center justify-center bg-black/45 p-4 backdrop-blur-[2px]"
          onClick={() => setLogoutConfirmOpen(false)}
        >
          <div
            className="w-full max-w-[280px] rounded-2xl border border-tg-border bg-tg-panel p-5 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h3 className="text-center text-lg font-semibold text-slate-900 dark:text-slate-100">
              Выйти из аккаунта?
            </h3>
            <p className="mt-2 text-center text-sm text-tg-muted">
              Вы уверены, что хотите выйти из своего аккаунта?
            </p>
            <div className="mt-5 flex flex-col gap-2.5">
              <button
                type="button"
                onClick={confirmLogout}
                className="w-full rounded-xl bg-red-500 py-2.5 text-sm font-semibold text-white transition hover:bg-red-600"
              >
                Выйти
              </button>
              <button
                type="button"
                onClick={() => setLogoutConfirmOpen(false)}
                className="w-full rounded-xl bg-tg-hover py-2.5 text-sm font-medium text-slate-800 transition hover:bg-tg-border dark:text-slate-200 dark:hover:bg-tg-border"
              >
                Отмена
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export function MessengerPage() {
  return (
    <MessengerProvider>
      <ChatWallpaperProvider>
        <CallProvider>
          <MessengerLayout />
        </CallProvider>
      </ChatWallpaperProvider>
    </MessengerProvider>
  );
}
