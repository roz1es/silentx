import type { Chat } from '@/types';
import { UserAvatar } from '@/components/UserAvatar';
import { chatParticipantLabel } from '@/lib/userDisplay';

type Props = {
  open: boolean;
  onClose: () => void;
  chat: Chat | null;
  onlineUserIds: string[];
  selfId: string;
  onMemberClick?: (userId: string) => void;
};

export function GroupMembersModal({
  open,
  onClose,
  chat,
  onlineUserIds,
  selfId,
  onMemberClick,
}: Props) {
  if (!open || !chat || chat.type !== 'group') return null;

  const parts = chat.participants ?? [];

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="max-h-[80vh] w-full max-w-md overflow-hidden rounded-2xl border border-tg-border bg-tg-panel shadow-2xl">
        <div className="border-b border-tg-border px-5 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
            Участники
          </h2>
          <p className="text-sm text-tg-muted">{chat.name}</p>
        </div>
        <ul className="scrollbar-thin max-h-[60vh] overflow-y-auto py-2">
          {parts.map((p) => {
            const online = onlineUserIds.includes(p.id);
            const isSelf = p.id === selfId;
            const label = chatParticipantLabel(p);
            return (
              <li key={p.id}>
                <button
                  type="button"
                  disabled={isSelf || !onMemberClick}
                  onClick={() => {
                    if (!isSelf && onMemberClick) {
                      onMemberClick(p.id);
                      onClose();
                    }
                  }}
                  className={`flex w-full items-center gap-3 px-4 py-2.5 text-left hover:bg-tg-hover ${
                    !isSelf && onMemberClick ? 'cursor-pointer' : 'cursor-default'
                  } disabled:opacity-100`}
                >
                <UserAvatar
                  username={label}
                  avatarUrl={p.avatarUrl}
                  size="sm"
                />
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium text-slate-900 dark:text-slate-100">
                    {label}
                    {isSelf ? (
                      <span className="ml-2 text-xs text-tg-muted">(вы)</span>
                    ) : null}
                  </p>
                  <p className="text-xs text-tg-muted">
                    {online ? 'в сети' : 'не в сети'}
                  </p>
                </div>
                <span
                  className={`h-2 w-2 shrink-0 rounded-full ${
                    online ? 'bg-emerald-500' : 'bg-slate-400'
                  }`}
                />
                </button>
              </li>
            );
          })}
        </ul>
        <div className="border-t border-tg-border px-4 py-3">
          <button
            type="button"
            onClick={onClose}
            className="w-full rounded-xl bg-tg-hover py-2 text-sm font-medium text-slate-800 dark:text-slate-200"
          >
            Закрыть
          </button>
        </div>
      </div>
    </div>
  );
}
