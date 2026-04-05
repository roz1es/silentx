import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import * as api from '@/lib/api';
import type { AdminOverview } from '@/lib/api';
import { IconArrowLeft } from '@/components/icons';
import { participantLabel } from '@/lib/userDisplay';

export function AdminPage() {
  const { user, logout } = useAuth();
  const [data, setData] = useState<AdminOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    api
      .fetchAdminOverview()
      .then((d) => {
        if (!cancelled) setData(d);
      })
      .catch((e) => {
        if (!cancelled)
          setError(e instanceof Error ? e.message : 'Ошибка загрузки');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="min-h-[100dvh] bg-tg-bg text-slate-900 dark:text-slate-100">
      <header className="border-b border-tg-border bg-tg-panel px-4 py-3 shadow-sm">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold tracking-tight">
              Админ-панель
            </h1>
            <p className="text-xs text-tg-muted">
              {user ? participantLabel(user) : ''}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Link
              to="/"
              className="inline-flex items-center gap-2 rounded-xl border border-tg-border bg-tg-hover px-3 py-2 text-sm font-medium transition hover:bg-tg-border/40"
            >
              <IconArrowLeft className="h-4 w-4 shrink-0" />
              Мессенджер
            </Link>
            <button
              type="button"
              onClick={logout}
              className="rounded-xl border border-tg-border bg-tg-panel px-3 py-2 text-sm font-semibold text-slate-700 transition-all duration-500 ease-out hover:border-red-300 hover:bg-red-500/10 hover:text-red-600 dark:text-slate-200 dark:hover:border-red-800 dark:hover:bg-red-500/15 dark:hover:text-red-400"
            >
              Выйти
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-5xl px-4 py-6">
        {loading ? (
          <p className="text-sm text-tg-muted">Загрузка…</p>
        ) : error ? (
          <p className="text-sm text-red-500">{error}</p>
        ) : data ? (
          <>
            <div className="mb-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <StatCard label="Пользователей" value={data.userCount} />
              <StatCard label="Чатов всего" value={data.chatCount} />
              <StatCard
                label="Сообщений"
                value={data.messageCount}
              />
              <div className="rounded-2xl border border-tg-border bg-tg-panel p-4 shadow-sm">
                <p className="text-xs font-medium uppercase tracking-wide text-tg-muted">
                  Типы чатов
                </p>
                <p className="mt-2 text-2xl font-semibold tabular-nums">
                  {data.directChatCount}{' '}
                  <span className="text-sm font-normal text-tg-muted">
                    личн. · {data.groupChatCount} групп
                  </span>
                </p>
              </div>
            </div>

            <div className="overflow-hidden rounded-2xl border border-tg-border bg-tg-panel shadow-sm">
              <div className="border-b border-tg-border px-4 py-3">
                <h2 className="text-sm font-semibold">Пользователи</h2>
              </div>
              <div className="scrollbar-thin max-h-[min(60vh,480px)] overflow-auto">
                <table className="w-full text-left text-sm">
                  <thead className="sticky top-0 bg-tg-hover/95 backdrop-blur-sm">
                    <tr className="border-b border-tg-border text-xs text-tg-muted">
                      <th className="px-4 py-2 font-medium">Ник</th>
                      <th className="px-4 py-2 font-medium">Имя</th>
                      <th className="px-4 py-2 font-medium">ID</th>
                      <th className="px-4 py-2 font-medium">Роль</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-tg-border/70">
                    {data.users.map((u) => (
                      <tr
                        key={u.id}
                        className="hover:bg-tg-hover/50 dark:hover:bg-slate-800/30"
                      >
                        <td className="px-4 py-2.5 font-medium">
                          @{u.username}
                        </td>
                        <td className="px-4 py-2.5 text-tg-muted">
                          {u.displayName?.trim() || '—'}
                        </td>
                        <td className="max-w-[140px] truncate px-4 py-2.5 font-mono text-[11px] text-tg-muted">
                          {u.id}
                        </td>
                        <td className="px-4 py-2.5">
                          {u.isAdmin ? (
                            <span className="rounded-full bg-slate-600 px-2 py-0.5 text-[11px] font-semibold text-white dark:bg-slate-500">
                              Админ
                            </span>
                          ) : (
                            <span className="text-tg-muted">—</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        ) : null}
      </main>
    </div>
  );
}

function StatCard({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-2xl border border-tg-border bg-tg-panel p-4 shadow-sm">
      <p className="text-xs font-medium uppercase tracking-wide text-tg-muted">
        {label}
      </p>
      <p className="mt-2 text-3xl font-semibold tabular-nums">{value}</p>
    </div>
  );
}
