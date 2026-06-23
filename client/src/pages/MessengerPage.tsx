import { useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
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
  const { user } = useAuth();
  const { username } = useParams<{ username?: string }>();
  const navigate = useNavigate();
  const { activeChat, selectChat, socketConnected, onlineUserIds, createDirect } =
    useMessenger();
  if (!user) return null;
  const [newInitialTab, setNewInitialTab] = useState<
    'direct' | 'group' | 'channel'
  >('direct');
  const [newOpen, setNewOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [groupOpen, setGroupOpen] = useState(false);
  const [mobileShowList, setMobileShowList] = useState(true);
  const [peerProfileId, setPeerProfileId] = useState<string | null>(null);
  const swipeStartRef = useRef<{ x: number; y: number } | null>(null);

  useEffect(() => {
    requestNotify();
  }, []);

  useEffect(() => {
    if (activeChat) setMobileShowList(false);
  }, [activeChat?.id]);

  useEffect(() => {
    const target = username?.trim().replace(/^@+/, '');
    if (!target) return;
    let cancelled = false;
    createDirect({ username: target })
      .then(() => {
        if (!cancelled) navigate('/', { replace: true });
      })
      .catch(() => {
        if (!cancelled) navigate('/', { replace: true });
      });
    return () => {
      cancelled = true;
    };
  }, [createDirect, navigate, username]);

  const showList = mobileShowList || !activeChat;

  const onChatTouchStart = (e: React.TouchEvent<HTMLElement>) => {
    if (window.innerWidth >= 768 || showList) return;
    const touch = e.touches[0];
    if (!touch) return;
    swipeStartRef.current = { x: touch.clientX, y: touch.clientY };
  };

  const onChatTouchEnd = (e: React.TouchEvent<HTMLElement>) => {
    const start = swipeStartRef.current;
    swipeStartRef.current = null;
    if (!start || window.innerWidth >= 768 || showList) return;
    const touch = e.changedTouches[0];
    if (!touch) return;
    const dx = touch.clientX - start.x;
    const dy = touch.clientY - start.y;
    const fromEdge = start.x <= 76;
    const deliberateSwipe = dx > 130 && Math.abs(dy) < 80;
    if ((fromEdge && dx > 72 && Math.abs(dy) < 70) || deliberateSwipe) {
      setMobileShowList(true);
      void selectChat(null);
    }
  };

  const directPeerChat =
    activeChat && activeChat.type === 'direct' ? activeChat : null;

  return (
    <div className="animated-bg flex h-[100dvh] w-full max-w-[100vw] flex-col overflow-hidden bg-tg-bg md:flex-row">
      <aside
        className={`relative flex min-h-0 w-full shrink-0 flex-col border-white/70 bg-white/70 shadow-[14px_0_42px_rgba(15,23,42,0.06)] backdrop-blur-2xl md:flex md:w-[min(100%,22rem)] md:border-r dark:border-white/10 dark:bg-zinc-800/55 dark:shadow-[14px_0_44px_rgba(0,0,0,0.18)] ${
          showList ? 'flex' : 'hidden md:flex'
        }`}
      >
        <div className="flex h-14 shrink-0 items-center gap-2 border-b border-white/70 bg-white/75 px-3 backdrop-blur-xl dark:border-white/10 dark:bg-zinc-800/45">
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
              <p
                className="min-h-4 text-[11px] text-tg-muted"
                aria-live="polite"
              >
                {socketConnected ? (
                  <span className="connection-online">БренксЧат · онлайн</span>
                ) : (
                  <span className="connection-pending">
                    соединение
                    <span className="connection-dots" aria-hidden>
                      <span />
                      <span />
                      <span />
                    </span>
                  </span>
                )}
              </p>
            </div>
          </button>
          <ThemeToggle />
          {user.isAdmin ? (
            <Link
              to="/admin"
              title="Админ-панель"
              aria-label="Админ-панель"
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-white/70 bg-white/65 text-tg-muted shadow-sm ring-1 ring-black/5 backdrop-blur-xl transition hover:bg-white hover:text-slate-800 dark:border-white/10 dark:bg-zinc-700/55 dark:ring-white/10 dark:hover:bg-zinc-700/85 dark:hover:text-slate-100"
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
        </div>
        <div className="min-h-0 min-w-0 flex-1">
          <ChatList
            onOpenNewChat={(tab) => {
              setNewInitialTab(tab);
              setNewOpen(true);
            }}
          />
        </div>
      </aside>

      <section
        onTouchStart={onChatTouchStart}
        onTouchEnd={onChatTouchEnd}
        onTouchCancel={() => {
          swipeStartRef.current = null;
        }}
        className={`flex min-h-0 min-w-0 max-w-full flex-1 flex-col overflow-hidden ${
          !showList ? 'flex' : 'hidden md:flex'
        }`}
      >
        <div className="flex items-center gap-0 bg-white/70 backdrop-blur-xl dark:bg-zinc-800/95">
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

      <NewChatModal
        open={newOpen}
        initialTab={newInitialTab}
        onClose={() => setNewOpen(false)}
      />
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
