import { useCallback, useEffect, useMemo, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import * as api from '@/lib/api';
import type { DirectoryUser } from '@/lib/api';
import { IconCheck, IconChevronRight, IconSearch } from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { participantLabel } from '@/lib/userDisplay';

type Props = {
  open: boolean;
  onClose: () => void;
};

function userLabel(u: DirectoryUser): string {
  return participantLabel(u);
}

export function NewChatModal({ open, onClose }: Props) {
  const { user } = useAuth();
  const { createDirect, createGroup, createChannel, onlineUserIds } =
    useMessenger();
  const [tab, setTab] = useState<'direct' | 'group' | 'channel'>('direct');
  const [directory, setDirectory] = useState<DirectoryUser[]>([]);
  const [search, setSearch] = useState('');
  const [groupName, setGroupName] = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [manualNick, setManualNick] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [dirLoading, setDirLoading] = useState(false);

  const loadDirectory = useCallback(async () => {
    setDirLoading(true);
    try {
      const { users } = await api.fetchUserDirectory();
      setDirectory(users);
    } catch {
      setDirectory([]);
    } finally {
      setDirLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    void loadDirectory();
    setError(null);
    setSearch('');
    setManualNick('');
    setGroupName('');
    setSelectedIds(new Set());
  }, [open, loadDirectory]);

  const filtered = useMemo(() => {
    const t = search.trim();
    if (!t) return directory;
    if (t.startsWith('@')) {
      const nick = t.slice(1).trim().toLowerCase();
      if (!nick) return directory;
      return directory.filter((u) =>
        u.username.toLowerCase().includes(nick)
      );
    }
    const q = t.toLowerCase();
    return directory.filter((u) => {
      const dn = u.displayName?.trim().toLowerCase() ?? '';
      return dn.length > 0 && dn.includes(q);
    });
  }, [directory, search]);

  const toggleMember = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const pickDirect = async (targetUserId: string) => {
    setError(null);
    setLoading(true);
    try {
      await createDirect({ userId: targetUserId });
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка');
    } finally {
      setLoading(false);
    }
  };

  const submitManualDirect = async () => {
    const nick = manualNick.trim().replace(/^@+/, '');
    if (nick.length < 2) {
      setError('Введите ник (от 2 символов)');
      return;
    }
    setError(null);
    setLoading(true);
    try {
      await createDirect({ username: nick });
      setManualNick('');
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка');
    } finally {
      setLoading(false);
    }
  };

  const submitGroup = async () => {
    if (groupName.trim().length < 2) {
      setError('Название группы — минимум 2 символа');
      return;
    }
    if (selectedIds.size === 0) {
      setError('Выберите хотя бы одного участника');
      return;
    }
    setError(null);
    setLoading(true);
    try {
      await createGroup(groupName.trim(), [...selectedIds]);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка');
    } finally {
      setLoading(false);
    }
  };

  const submitChannel = async () => {
    if (groupName.trim().length < 2) {
      setError('Название канала — минимум 2 символа');
      return;
    }
    setError(null);
    setLoading(true);
    try {
      await createChannel(groupName.trim(), [...selectedIds]);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка');
    } finally {
      setLoading(false);
    }
  };

  if (!open || !user) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/45 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="flex max-h-[min(90dvh,640px)] w-full max-w-lg flex-col overflow-hidden rounded-2xl border border-tg-border bg-tg-panel shadow-2xl">
        <div className="shrink-0 border-b border-tg-border px-5 py-4">
          <h2 className="text-lg font-semibold text-slate-800 dark:text-slate-100">
            Новый чат
          </h2>
          <p className="mt-1 text-xs text-tg-muted">
            Выберите человека из списка — все зарегистрированные пользователи видны здесь
          </p>
          <div className="relative mt-4 flex gap-1 rounded-2xl border border-tg-border/70 bg-tg-hover/90 p-1 dark:border-slate-600/80 dark:bg-slate-800/80">
            <span
              className="pointer-events-none absolute bottom-1 top-1 left-1 rounded-xl bg-tg-panel shadow-md transition-transform duration-500 ease-[cubic-bezier(0.22,1,0.36,1)] will-change-transform dark:bg-slate-700 dark:shadow-black/30"
              style={{
                width: 'calc((100% - 8px - 8px) / 3)',
                transform:
                  tab === 'direct'
                    ? 'translateX(0)'
                    : tab === 'group'
                      ? 'translateX(calc(100% + 4px))'
                      : 'translateX(calc(200% + 8px))',
              }}
            />
            <button
              type="button"
              className={`relative z-10 min-h-[2.5rem] flex-1 rounded-xl py-2 text-sm font-medium transition-colors duration-500 ${
                tab === 'direct'
                  ? 'text-slate-800 dark:text-slate-100'
                  : 'text-tg-muted hover:text-slate-600 dark:hover:text-slate-300'
              }`}
              onClick={() => setTab('direct')}
            >
              Личный
            </button>
            <button
              type="button"
              className={`relative z-10 min-h-[2.5rem] flex-1 rounded-xl py-2 text-sm font-medium transition-colors duration-500 ${
                tab === 'group'
                  ? 'text-slate-800 dark:text-slate-100'
                  : 'text-tg-muted hover:text-slate-600 dark:hover:text-slate-300'
              }`}
              onClick={() => setTab('group')}
            >
              Группа
            </button>
            <button
              type="button"
              className={`relative z-10 min-h-[2.5rem] flex-1 rounded-xl py-2 text-sm font-medium transition-colors duration-500 ${
                tab === 'channel'
                  ? 'text-slate-800 dark:text-slate-100'
                  : 'text-tg-muted hover:text-slate-600 dark:hover:text-slate-300'
              }`}
              onClick={() => setTab('channel')}
            >
              Канал
            </button>
          </div>
        </div>

        <div className="min-h-0 flex-1 overflow-hidden px-5 py-3">
          <div className="relative mb-3">
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-tg-muted">
              <IconSearch className="h-4 w-4" />
            </span>
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Поиск..."
              className="w-full rounded-xl border border-tg-border bg-white py-2.5 pl-9 pr-3 text-sm outline-none ring-tg-accent/25 focus:ring-2 dark:bg-slate-900/40 dark:text-slate-100"
            />
          </div>

          {tab === 'group' || tab === 'channel' ? (
            <div className="mb-3">
              <input
                value={groupName}
                onChange={(e) => setGroupName(e.target.value)}
                placeholder={
                  tab === 'channel' ? 'Название канала' : 'Название группы'
                }
                className="w-full rounded-xl border border-tg-border bg-white px-3 py-2.5 text-sm font-medium outline-none ring-tg-accent/25 focus:ring-2 dark:bg-slate-900/40 dark:text-slate-100"
              />
              {selectedIds.size > 0 ? (
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {[...selectedIds].map((id) => {
                    const u = directory.find((x) => x.id === id);
                    if (!u) return null;
                    return (
                      <button
                        key={id}
                        type="button"
                        onClick={() => toggleMember(id)}
                        className="inline-flex items-center gap-1 rounded-full bg-tg-mine px-2.5 py-1 text-xs font-medium text-slate-700 dark:text-slate-200"
                      >
                        {userLabel(u)}
                        <span className="text-tg-muted">×</span>
                      </button>
                    );
                  })}
                </div>
              ) : (
                <p className="mt-2 text-xs text-tg-muted">
                  {tab === 'channel'
                    ? 'Подписчики только читают. Добавьте людей ниже или оставьте канал только для себя.'
                    : 'Нажмите на людей ниже — они попадут в группу'}
                </p>
              )}
            </div>
          ) : null}

          <div className="scrollbar-thin max-h-[min(50vh,320px)] overflow-y-auto rounded-xl border border-tg-border/80 bg-tg-hover/40 dark:bg-slate-900/20">
            {dirLoading ? (
              <p className="px-4 py-8 text-center text-sm text-tg-muted">
                Загрузка списка…
              </p>
            ) : filtered.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-tg-muted">
                Никого не найдено
              </p>
            ) : (
              <ul className="divide-y divide-tg-border/50">
                {filtered.map((u) => {
                  const online = onlineUserIds.includes(u.id);
                  const selected = selectedIds.has(u.id);
                  if (tab === 'direct') {
                    return (
                      <li key={u.id}>
                        <button
                          type="button"
                          disabled={loading}
                          onClick={() => void pickDirect(u.id)}
                          className="flex w-full items-center gap-3 px-3 py-2.5 text-left transition hover:bg-tg-hover disabled:opacity-50"
                        >
                          <UserAvatar
                            username={userLabel(u)}
                            avatarUrl={u.avatarUrl}
                            size="md"
                          />
                          <div className="min-w-0 flex-1">
                            <p className="truncate font-medium text-slate-800 dark:text-slate-100">
                              {userLabel(u)}
                            </p>
                            <p className="truncate text-xs text-tg-muted">
                              @{u.username}
                              {online ? (
                                <span className="ml-2 text-emerald-600 dark:text-emerald-400">
                                  · в сети
                                </span>
                              ) : null}
                            </p>
                          </div>
                          <IconChevronRight className="h-4 w-4 shrink-0 text-tg-muted" />
                        </button>
                      </li>
                    );
                  }
                  return (
                    <li key={u.id}>
                      <button
                        type="button"
                        disabled={loading}
                        onClick={() => toggleMember(u.id)}
                        className={`flex w-full items-center gap-3 px-3 py-2.5 text-left transition hover:bg-tg-hover disabled:opacity-50 ${
                          selected ? 'bg-tg-mine/80 dark:bg-slate-800/50' : ''
                        }`}
                      >
                        <span
                          className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-md border-2 ${
                            selected
                              ? 'border-tg-accent bg-tg-accent text-white'
                              : 'border-tg-border text-transparent'
                          }`}
                        >
                          {selected ? (
                            <IconCheck className="h-3.5 w-3.5" />
                          ) : null}
                        </span>
                        <UserAvatar
                          username={userLabel(u)}
                          avatarUrl={u.avatarUrl}
                          size="md"
                        />
                        <div className="min-w-0 flex-1">
                          <p className="truncate font-medium text-slate-800 dark:text-slate-100">
                            {userLabel(u)}
                          </p>
                          <p className="truncate text-xs text-tg-muted">
                            @{u.username}
                            {online ? (
                              <span className="ml-2 text-emerald-600 dark:text-emerald-400">
                                · в сети
                              </span>
                            ) : null}
                          </p>
                        </div>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>

          {tab === 'direct' ? (
            <div className="mt-3 rounded-xl border border-dashed border-tg-border bg-tg-hover/30 px-3 py-2.5">
              <p className="mb-1.5 text-[11px] font-medium uppercase tracking-wide text-tg-muted">
                Или введите ник вручную
              </p>
              <div className="flex gap-2">
                <input
                  value={manualNick}
                  onChange={(e) => setManualNick(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') void submitManualDirect();
                  }}
                  placeholder="ник (без @)"
                  className="min-w-0 flex-1 rounded-lg border border-tg-border bg-white px-3 py-2 text-sm dark:bg-slate-900/40 dark:text-slate-100"
                />
                <button
                  type="button"
                  disabled={loading}
                  onClick={() => void submitManualDirect()}
                  className="shrink-0 rounded-lg bg-tg-accent px-3 py-2 text-sm font-semibold text-white hover:brightness-105 disabled:opacity-50"
                >
                  OK
                </button>
              </div>
            </div>
          ) : null}
        </div>

        {error ? (
          <p className="shrink-0 px-5 pb-2 text-sm text-red-500 dark:text-red-400">
            {error}
          </p>
        ) : null}

        <div className="flex shrink-0 justify-end gap-2 border-t border-tg-border px-5 py-4">
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl px-4 py-2 text-sm font-medium text-tg-muted hover:bg-tg-hover"
          >
            Закрыть
          </button>
          {tab === 'group' ? (
            <button
              type="button"
              disabled={loading || selectedIds.size === 0}
              onClick={() => void submitGroup()}
              className="rounded-xl bg-tg-accent px-5 py-2 text-sm font-semibold text-white shadow hover:brightness-105 disabled:cursor-not-allowed disabled:opacity-40"
            >
              {loading ? '…' : `Создать · ${selectedIds.size} чел.`}
            </button>
          ) : null}
          {tab === 'channel' ? (
            <button
              type="button"
              disabled={loading}
              onClick={() => void submitChannel()}
              className="rounded-xl bg-tg-accent px-5 py-2 text-sm font-semibold text-white shadow hover:brightness-105 disabled:cursor-not-allowed disabled:opacity-40"
            >
              {loading
                ? '…'
                : selectedIds.size > 0
                  ? `Создать канал · ${selectedIds.size} подп.`
                  : 'Создать канал'}
            </button>
          ) : null}
        </div>
      </div>
    </div>
  );
}
