import { useEffect, useState } from 'react';
import * as api from '@/lib/api';
import type { User } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { participantLabel } from '@/lib/userDisplay';
import { UserAvatar } from '@/components/UserAvatar';

type Props = {
  userId: string | null;
  onClose: () => void;
};

export function PeerProfileModal({ userId, onClose }: Props) {
  const { user: viewer } = useAuth();
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!userId) {
      setUser(null);
      setError(null);
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError(null);
    setUser(null);
    api
      .fetchUserProfile(userId)
      .then(({ user: u }) => {
        if (!cancelled) setUser(u);
      })
      .catch((e: Error) => {
        if (!cancelled) setError(e.message ?? 'Ошибка загрузки');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [userId]);

  if (!userId) return null;

  const label = user ? participantLabel(user) : '…';

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="w-full max-w-sm rounded-2xl border border-tg-border bg-tg-panel p-6 shadow-2xl">
        <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
          Профиль
        </h2>
        {loading ? (
          <p className="mt-6 text-center text-sm text-tg-muted">Загрузка…</p>
        ) : error ? (
          <p className="mt-6 text-center text-sm text-red-500">{error}</p>
        ) : user ? (
          <div className="mt-6 flex flex-col items-center gap-4 text-center">
            <UserAvatar
              username={label}
              avatarUrl={user.avatarUrl}
              size="lg"
            />
            <div>
              <p className="text-base font-semibold text-slate-900 dark:text-slate-100">
                {label}
              </p>
              <p className="text-sm text-tg-muted">@{user.username}</p>
            </div>
            {viewer?.isAdmin ? (
              <div className="w-full rounded-xl bg-tg-hover px-3 py-2 text-left">
                <p className="text-[11px] uppercase tracking-wide text-tg-muted">
                  ID
                </p>
                <p className="break-all font-mono text-xs text-slate-800 dark:text-slate-200">
                  {user.id}
                </p>
              </div>
            ) : null}
            {user.phone?.trim() ? (
              <div className="w-full rounded-xl bg-tg-hover px-3 py-2 text-left">
                <p className="text-[11px] uppercase tracking-wide text-tg-muted">
                  Телефон
                </p>
                <p className="text-sm text-slate-800 dark:text-slate-100">
                  {user.phone}
                </p>
              </div>
            ) : null}
            {user.birthDate ? (
              <div className="w-full rounded-xl bg-tg-hover px-3 py-2 text-left">
                <p className="text-[11px] uppercase tracking-wide text-tg-muted">
                  Дата рождения
                </p>
                <p className="text-sm text-slate-800 dark:text-slate-100">
                  {new Intl.DateTimeFormat('ru', {
                    day: 'numeric',
                    month: 'long',
                    year: 'numeric',
                  }).format(new Date(user.birthDate + 'T12:00:00'))}
                </p>
              </div>
            ) : null}
            {user.bio?.trim() ? (
              <p className="w-full text-left text-sm text-slate-700 dark:text-slate-200">
                {user.bio}
              </p>
            ) : (
              <p className="text-sm text-tg-muted">Нет описания</p>
            )}
          </div>
        ) : null}
        <button
          type="button"
          onClick={onClose}
          className="mt-6 w-full rounded-xl border border-tg-border py-2 text-sm font-medium text-tg-muted"
        >
          Закрыть
        </button>
      </div>
    </div>
  );
}
