import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import * as api from '@/lib/api';
import type { AdminOverview } from '@/lib/api';
import { IconArrowLeft, IconDatabase } from '@/components/icons';
import { participantLabel } from '@/lib/userDisplay';

export function AdminPage() {
  const { user, logout } = useAuth();
  const [data, setData] = useState<AdminOverview | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busyUserId, setBusyUserId] = useState<string | null>(null);
  const [databaseUrl, setDatabaseUrl] = useState<string | null>(null);

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

  useEffect(() => {
    let cancelled = false;
    api
      .fetchAdminDatabaseLink()
      .then(({ url }) => {
        if (!cancelled) setDatabaseUrl(url);
      })
      .catch(() => {
        if (!cancelled) setDatabaseUrl(null);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const toggleBlock = async (userId: string, banned: boolean) => {
    setBusyUserId(userId);
    setError(null);
    try {
      await api.setAdminUserBlocked(userId, banned);
      const fresh = await api.fetchAdminOverview();
      setData(fresh);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось изменить статус');
    } finally {
      setBusyUserId(null);
    }
  };

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
            {databaseUrl ? (
              <a
                href={databaseUrl}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-2 rounded-xl border border-sky-400/25 bg-sky-500/10 px-3 py-2 text-sm font-semibold text-sky-700 transition hover:border-sky-400/45 hover:bg-sky-500/16 dark:text-sky-300"
                title="Открыть phpMyAdmin"
              >
                <IconDatabase className="h-4 w-4 shrink-0" />
                БД
              </a>
            ) : null}
            <Link
              to="/"
              className="inline-flex items-center gap-2 rounded-xl border border-tg-border bg-tg-hover px-3 py-2 text-sm font-medium transition hover:bg-tg-border/40"
            >
              <IconArrowLeft className="h-4 w-4 shrink-0" />
              Мессенджер
            </Link>
            <button
              type="button"
              onClick={() => void logout()}
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
              <StatCard label="Заблокировано" value={data.blockedUserCount} />
              <StatCard label="Чатов всего" value={data.chatCount} />
              <StatCard
                label="Сообщений"
                value={data.messageCount}
              />
              <div className="rounded-2xl border border-tg-border bg-tg-panel p-4 shadow-sm sm:col-span-2 lg:col-span-4">
                <p className="text-xs font-medium uppercase tracking-wide text-tg-muted">
                  Типы чатов
                </p>
                <p className="mt-2 text-2xl font-semibold tabular-nums">
                  {data.directChatCount}{' '}
                  <span className="text-sm font-normal text-tg-muted">
                    личн. · {data.groupChatCount} групп · {data.channelChatCount} каналов
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
                      <th className="px-4 py-2 font-medium">Почта</th>
                      <th className="px-4 py-2 font-medium">Активность</th>
                      <th className="px-4 py-2 font-medium">Роль</th>
                      <th className="px-4 py-2 font-medium">Действие</th>
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
                        <td className="max-w-[180px] truncate px-4 py-2.5 text-tg-muted">
                          {u.email ? (
                            <>
                              {u.email}{' '}
                              <span className={u.emailVerified ? 'text-emerald-500' : 'text-amber-500'}>
                                {u.emailVerified ? 'OK' : 'код'}
                              </span>
                            </>
                          ) : (
                            '—'
                          )}
                        </td>
                        <td className="px-4 py-2.5 text-tg-muted">
                          {u.messageCount} сообщ. · {u.chatCount} чат.
                        </td>
                        <td className="px-4 py-2.5">
                          {u.isAdmin ? (
                            <span className="rounded-full bg-slate-600 px-2 py-0.5 text-[11px] font-semibold text-white dark:bg-slate-500">
                              Админ
                            </span>
                          ) : (
                            <span
                              className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                                u.banned
                                  ? 'bg-red-100 text-red-700 dark:bg-red-400/10 dark:text-red-300'
                                  : 'bg-emerald-100 text-emerald-700 dark:bg-emerald-400/10 dark:text-emerald-300'
                              }`}
                            >
                              {u.banned ? 'Блок' : 'Польз.'}
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-2.5">
                          {u.isAdmin || u.id === user?.id ? (
                            <span className="text-xs text-tg-muted">—</span>
                          ) : (
                            <button
                              type="button"
                              disabled={busyUserId === u.id}
                              onClick={() => void toggleBlock(u.id, !u.banned)}
                              className={`rounded-xl px-3 py-1.5 text-xs font-semibold transition disabled:opacity-50 ${
                                u.banned
                                  ? 'bg-emerald-500/12 text-emerald-600 hover:bg-emerald-500/18'
                                  : 'bg-red-500/10 text-red-600 hover:bg-red-500/15'
                              }`}
                            >
                              {busyUserId === u.id
                                ? '...'
                                : u.banned
                                  ? 'Разблок.'
                                  : 'Блок'}
                            </button>
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
