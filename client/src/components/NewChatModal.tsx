import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import * as api from '@/lib/api';
import type { DirectoryUser } from '@/lib/api';
import { IconCheck, IconChevronRight, IconSearch } from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { participantLabel } from '@/lib/userDisplay';
import { isWaitingForSearchInput, userSearchQuery } from '@/lib/userSearch';

type Props = {
  open: boolean;
  onClose: () => void;
  initialTab?: 'direct' | 'group' | 'channel';
};

function userLabel(u: DirectoryUser): string {
  return participantLabel(u);
}

export function NewChatModal({ open, onClose, initialTab = 'direct' }: Props) {
  const { user } = useAuth();
  const { createDirect, createGroup, createChannel, onlineUserIds } =
    useMessenger();
  const [tab, setTab] = useState<'direct' | 'group' | 'channel'>('direct');
  const [directory, setDirectory] = useState<DirectoryUser[]>([]);
  const [search, setSearch] = useState('');
  const [groupName, setGroupName] = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [dirLoading, setDirLoading] = useState(false);
  const listRef = useRef<HTMLDivElement | null>(null);
  const memberBtnRefById = useRef<Record<string, HTMLButtonElement | null>>({});

  const loadDirectory = useCallback(async (mode: 'direct' | 'group' | 'channel') => {
    if (mode === 'direct') {
      setDirectory([]);
      setDirLoading(false);
      return;
    }
    setDirLoading(true);
    try {
      const { users } =
        await api.fetchContactDirectory();
      setDirectory(users);
    } catch {
      setDirectory([]);
    } finally {
      setDirLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    setTab(initialTab);
    setError(null);
    setGroupName('');
  }, [open, initialTab]);

  useEffect(() => {
    if (!open) return;
    void loadDirectory(tab);
    setSearch('');
    setSelectedIds(new Set());
    setError(null);
  }, [open, tab, loadDirectory]);

  useEffect(() => {
    if (!open || tab !== 'direct') return;
    const query = userSearchQuery(search, { allowPlainUsername: true });
    if (!query) {
      setDirectory([]);
      setDirLoading(false);
      return;
    }
    let alive = true;
    setDirLoading(true);
    const timer = window.setTimeout(() => {
      api
        .searchUsers(query)
        .then(({ users }) => {
          if (alive) setDirectory(users);
        })
        .catch(() => {
          if (alive) setDirectory([]);
        })
        .finally(() => {
          if (alive) setDirLoading(false);
        });
    }, 240);
    return () => {
      alive = false;
      window.clearTimeout(timer);
    };
  }, [open, tab, search]);

  const filtered = useMemo(() => {
    if (tab === 'direct') return directory;
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
  }, [directory, search, tab]);

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
      className="brenks-modal-backdrop fixed inset-0 z-50 flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="brenks-modal-panel flex max-h-[min(90dvh,660px)] w-full max-w-md flex-col overflow-hidden rounded-[1.6rem]">
        <div className="shrink-0 px-5 pb-4 pt-5">
          <div className="mb-4 flex items-center justify-between gap-3">
            <div>
              <h2 className="text-xl font-semibold tracking-normal text-slate-900 dark:text-slate-100">
                Новый чат
              </h2>
              <p className="mt-1 text-sm text-tg-muted">
                {tab === 'direct'
                  ? 'Введите @username или ID пользователя'
                  : 'Добавляйте людей из ваших личных чатов'}
              </p>
            </div>
            <button
              type="button"
              onClick={onClose}
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-tg-hover text-tg-muted transition hover:bg-tg-border hover:text-slate-900 dark:hover:text-slate-100"
              title="Закрыть"
            >
              ×
            </button>
          </div>
          <div className="brenks-modal-field relative flex gap-1 rounded-[1.35rem] p-1 shadow-inner">
            <span
              className="pointer-events-none absolute bottom-1 left-1 top-1 rounded-2xl bg-white shadow-[0_8px_24px_rgba(15,23,42,0.10)] transition-transform duration-500 ease-[cubic-bezier(0.22,1,0.36,1)] will-change-transform dark:bg-zinc-700 dark:shadow-black/25"
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
              className={`relative z-10 min-h-[2.5rem] flex-1 rounded-2xl py-2 text-sm font-semibold transition-colors duration-500 ${
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
              className={`relative z-10 min-h-[2.5rem] flex-1 rounded-2xl py-2 text-sm font-semibold transition-colors duration-500 ${
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
              className={`relative z-10 min-h-[2.5rem] flex-1 rounded-2xl py-2 text-sm font-semibold transition-colors duration-500 ${
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

        <div className="min-h-0 flex-1 overflow-hidden border-t border-tg-border/70 px-5 py-4">
          <div className="relative mb-3">
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-tg-muted">
              <IconSearch className="h-4 w-4" />
            </span>
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder={
                tab === 'direct' ? '@username или ID' : 'Поиск по контактам...'
              }
              className="brenks-modal-input w-full rounded-2xl border border-tg-border bg-white/95 py-3 pl-10 pr-3 text-sm outline-none shadow-sm ring-tg-accent/20 transition focus:ring-2 dark:bg-zinc-900/60"
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
                className="brenks-modal-input w-full rounded-2xl border border-tg-border bg-white/95 px-3 py-3 text-sm font-medium outline-none shadow-sm ring-tg-accent/20 focus:ring-2 dark:bg-zinc-900/60"
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
                    ? 'Подписчики только читают. В списке ниже только ваши контакты.'
                    : 'Нажмите на контакты ниже — они попадут в группу'}
                </p>
              )}
            </div>
          ) : null}

          <div
            ref={listRef}
            className="brenks-modal-list scrollbar-thin scroll-smooth max-h-[min(50vh,320px)] overflow-y-auto rounded-2xl p-1 shadow-inner"
          >
            {dirLoading ? (
              <p className="px-4 py-8 text-center text-sm text-tg-muted">
                Загрузка списка…
              </p>
            ) : filtered.length === 0 ? (
              <p className="px-4 py-8 text-center text-sm text-tg-muted">
                {tab === 'direct'
                  ? isWaitingForSearchInput(search, {
                      allowPlainUsername: true,
                    })
                    ? 'Введите @username, username или ID пользователя'
                    : 'Пользователь не найден'
                  : 'Пока нет контактов. Сначала найдите пользователя через @username и откройте личный чат.'}
              </p>
            ) : (
              <ul className="space-y-1">
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
                          className="brenks-modal-row flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-left transition hover:shadow-sm disabled:opacity-50"
                        >
                          <UserAvatar
                            username={userLabel(u)}
                            avatarUrl={u.avatarUrl}
                            size="md"
                          />
                          <div className="min-w-0 flex-1">
                            <p className="truncate font-semibold">
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
                        ref={(el) => {
                          memberBtnRefById.current[u.id] = el;
                        }}
                        onClick={() => {
                          toggleMember(u.id);
                          requestAnimationFrame(() => {
                            memberBtnRefById.current[u.id]?.scrollIntoView({
                              behavior: 'smooth',
                              block: 'nearest',
                            });
                          });
                        }}
                        className={`brenks-modal-row flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-left transition hover:shadow-sm disabled:opacity-50 ${
                          selected ? 'bg-sky-100/75 shadow-sm dark:bg-zinc-700/70' : ''
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
                          <p className="truncate font-semibold">
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

        </div>

        {error ? (
          <p className="shrink-0 px-5 pb-2 text-sm text-red-500 dark:text-red-400">
            {error}
          </p>
        ) : null}

        <div className="flex shrink-0 justify-end gap-2 border-t border-tg-border/70 bg-tg-hover/25 px-5 py-4 backdrop-blur-xl">
          <button
            type="button"
            onClick={onClose}
            className="rounded-2xl px-4 py-2 text-sm font-semibold text-tg-muted hover:bg-tg-hover"
          >
            Закрыть
          </button>
          {tab === 'group' ? (
            <button
              type="button"
              disabled={loading || selectedIds.size === 0}
              onClick={() => void submitGroup()}
              className="rounded-2xl bg-slate-900 px-5 py-2 text-sm font-semibold text-white shadow hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-40 dark:bg-slate-100 dark:text-slate-950"
            >
              {loading ? '…' : `Создать · ${selectedIds.size} чел.`}
            </button>
          ) : null}
          {tab === 'channel' ? (
            <button
              type="button"
              disabled={loading}
              onClick={() => void submitChannel()}
              className="rounded-2xl bg-slate-900 px-5 py-2 text-sm font-semibold text-white shadow hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-40 dark:bg-slate-100 dark:text-slate-950"
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
