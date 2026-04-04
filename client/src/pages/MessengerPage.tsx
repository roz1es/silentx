import { useEffect, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { MessengerProvider, useMessenger } from '@/contexts/MessengerContext';
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

  useEffect(() => {
    requestNotify();
  }, []);

  useEffect(() => {
    if (activeChat) setMobileShowList(false);
  }, [activeChat?.id]);

  const showList = mobileShowList || !activeChat;

  const directPeerChat =
    activeChat && activeChat.type !== 'group' ? activeChat : null;

  return (
    <div className="flex h-[100dvh] w-full flex-col overflow-hidden bg-tg-bg md:flex-row">
      <aside
        className={`flex min-h-0 w-full shrink-0 flex-col border-tg-border md:flex md:w-[min(100%,22rem)] md:border-r ${
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
                {socketConnected ? 'Silentix · онлайн' : 'соединение…'}
              </p>
            </div>
          </button>
          <ThemeToggle />
          <button
            type="button"
            onClick={() => setNewOpen(true)}
            className="rounded-full bg-tg-accent px-3 py-1.5 text-xs font-semibold text-white shadow hover:brightness-105"
          >
            + Чат
          </button>
          <button
            type="button"
            onClick={logout}
            className="rounded-full px-2 py-1 text-xs text-tg-muted hover:bg-tg-hover"
          >
            Выход
          </button>
        </div>
        <div className="min-h-0 flex-1">
          <ChatList />
        </div>
      </aside>

      <section
        className={`flex min-h-0 min-w-0 flex-1 flex-col ${
          !showList ? 'flex' : 'hidden md:flex'
        }`}
      >
        <div className="flex items-center gap-0 bg-tg-panel">
          <button
            type="button"
            className="px-2 py-3 text-tg-muted md:hidden"
            aria-label="Назад к списку"
            onClick={() => {
              setMobileShowList(true);
              void selectChat(null);
            }}
          >
            ←
          </button>
          <div className="min-w-0 flex-1">
            <ChatHeader
              onGroupInfo={
                activeChat?.type === 'group'
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
    </div>
  );
}

export function MessengerPage() {
  return (
    <MessengerProvider>
      <MessengerLayout />
    </MessengerProvider>
  );
}
