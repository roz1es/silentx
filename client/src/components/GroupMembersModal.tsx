import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { Chat, ChatParticipant } from '@/types';
import { UserAvatar } from '@/components/UserAvatar';
import { chatParticipantLabel } from '@/lib/userDisplay';
import { ruMembers, ruSubscribers } from '@/lib/pluralRu';
import * as api from '@/lib/api';
import type { DirectoryUser } from '@/lib/api';
import { IconCheck } from '@/components/icons';
import { useMessenger } from '@/contexts/MessengerContext';

const MAX_PHOTO = 600 * 1024;

type Props = {
  open: boolean;
  onClose: () => void;
  chat: Chat | null;
  onlineUserIds: string[];
  selfId: string;
  onMemberClick?: (userId: string) => void;
};

function buildMemberList(chat: Chat): ChatParticipant[] {
  const ids = chat.participantIds ?? [];
  const known = chat.participants ?? [];
  const map = new Map(known.map((p) => [p.id, p]));
  const rows: ChatParticipant[] = ids.map((id) => {
    const p = map.get(id);
    if (p) return p;
    return {
      id,
      username: 'user',
      displayName: `Участник · ${id.slice(-6)}`,
    };
  });
  if (chat.type === 'channel' && chat.channelOwnerId) {
    const owner = rows.filter((r) => r.id === chat.channelOwnerId);
    const rest = rows.filter((r) => r.id !== chat.channelOwnerId);
    rest.sort((a, b) =>
      chatParticipantLabel(a).localeCompare(chatParticipantLabel(b), 'ru')
    );
    return [...owner, ...rest];
  }
  return rows;
}

function readFileAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(new Error('read'));
    r.readAsDataURL(file);
  });
}

export function GroupMembersModal({
  open,
  onClose,
  chat,
  onlineUserIds,
  selfId,
  onMemberClick,
}: Props) {
  const { patchChat, addChatMembers, refreshChats } = useMessenger();
  const [nameDraft, setNameDraft] = useState('');
  const [saving, setSaving] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [addOpen, setAddOpen] = useState(false);
  const [directory, setDirectory] = useState<DirectoryUser[]>([]);
  const [pickIds, setPickIds] = useState<Set<string>>(new Set());
  const [dirLoading, setDirLoading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const canManage = useMemo(() => {
    if (!chat) return false;
    if (chat.type === 'group') return chat.participantIds.includes(selfId);
    if (chat.type === 'channel') return chat.channelOwnerId === selfId;
    return false;
  }, [chat, selfId]);

  useEffect(() => {
    if (!open || !chat) return;
    setNameDraft(chat.name);
    setErr(null);
    setAddOpen(false);
    setPickIds(new Set());
  }, [open, chat?.id, chat?.name]);

  const loadDir = useCallback(async () => {
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
    if (open && addOpen) void loadDir();
  }, [open, addOpen, loadDir]);

  if (!open || !chat || (chat.type !== 'group' && chat.type !== 'channel'))
    return null;

  const parts = buildMemberList(chat);
  const count = parts.length;
  const participantSet = new Set(chat.participantIds);

  const saveMeta = async () => {
    if (!canManage) return;
    setErr(null);
    setSaving(true);
    try {
      await patchChat(chat.id, { name: nameDraft.trim() });
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Ошибка');
    } finally {
      setSaving(false);
    }
  };

  const onPickAvatar = async (files: FileList | null) => {
    const f = files?.[0];
    if (!f?.type.startsWith('image/')) return;
    if (f.size > MAX_PHOTO) {
      setErr('Фото до 600 КБ');
      return;
    }
    setErr(null);
    setSaving(true);
    try {
      const dataUrl = await readFileAsDataUrl(f);
      await patchChat(chat.id, { avatarUrl: dataUrl });
    } catch {
      setErr('Не удалось сохранить фото');
    } finally {
      setSaving(false);
    }
  };

  const removeAvatar = async () => {
    setSaving(true);
    try {
      await patchChat(chat.id, { avatarUrl: null });
    } finally {
      setSaving(false);
    }
  };

  const submitAdd = async () => {
    if (pickIds.size === 0) return;
    setSaving(true);
    setErr(null);
    try {
      await addChatMembers(chat.id, [...pickIds]);
      await refreshChats().catch(() => {});
      setPickIds(new Set());
      setAddOpen(false);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Ошибка');
    } finally {
      setSaving(false);
    }
  };

  const togglePick = (id: string) => {
    setPickIds((prev) => {
      const n = new Set(prev);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });
  };

  const addCandidates = directory.filter((u) => !participantSet.has(u.id));

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="max-h-[85vh] w-full max-w-md overflow-hidden rounded-2xl border border-tg-border bg-tg-panel shadow-2xl">
        <div className="border-b border-tg-border px-5 py-4">
          <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
            {chat.type === 'channel' ? 'Канал' : 'Группа'}
          </h2>
          {canManage ? (
            <div className="mt-4 space-y-3">
              <div className="flex items-center gap-3">
                {chat.avatarUrl ? (
                  <img
                    src={chat.avatarUrl}
                    alt=""
                    className="h-14 w-14 shrink-0 rounded-full object-cover ring-2 ring-tg-border"
                  />
                ) : (
                  <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-tg-accent text-lg font-bold text-white">
                    {chat.name.slice(0, 1).toUpperCase()}
                  </div>
                )}
                <div className="flex min-w-0 flex-1 flex-col gap-1">
                  <input
                    type="file"
                    ref={fileRef}
                    accept="image/*"
                    className="hidden"
                    onChange={(e) => void onPickAvatar(e.target.files)}
                  />
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      disabled={saving}
                      onClick={() => fileRef.current?.click()}
                      className="rounded-lg bg-tg-accent px-3 py-1.5 text-xs font-semibold text-white disabled:opacity-50"
                    >
                      Фото
                    </button>
                    {chat.avatarUrl ? (
                      <button
                        type="button"
                        disabled={saving}
                        onClick={() => void removeAvatar()}
                        className="rounded-lg bg-tg-hover px-3 py-1.5 text-xs text-slate-700 dark:text-slate-200"
                      >
                        Убрать
                      </button>
                    ) : null}
                  </div>
                </div>
              </div>
              <div>
                <label className="text-xs text-tg-muted" htmlFor="gcm-name">
                  Название
                </label>
                <div className="mt-1 flex gap-2">
                  <input
                    id="gcm-name"
                    value={nameDraft}
                    onChange={(e) => setNameDraft(e.target.value)}
                    maxLength={128}
                    className="min-w-0 flex-1 rounded-xl border border-tg-border bg-white px-3 py-2 text-sm dark:bg-slate-900/40 dark:text-slate-100"
                  />
                  <button
                    type="button"
                    disabled={saving || nameDraft.trim().length < 2}
                    onClick={() => void saveMeta()}
                    className="shrink-0 rounded-xl bg-tg-hover px-3 py-2 text-sm font-medium disabled:opacity-40"
                  >
                    OK
                  </button>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setAddOpen((o) => !o)}
                className="w-full rounded-xl border border-tg-border py-2 text-sm font-medium text-tg-accent"
              >
                {addOpen ? 'Скрыть выбор' : 'Добавить участников'}
              </button>
              {addOpen ? (
                <div className="max-h-48 overflow-y-auto rounded-xl border border-tg-border bg-tg-hover/30 p-2 dark:bg-slate-900/30">
                  {dirLoading ? (
                    <p className="py-4 text-center text-sm text-tg-muted">
                      Загрузка…
                    </p>
                  ) : addCandidates.length === 0 ? (
                    <p className="py-4 text-center text-sm text-tg-muted">
                      Некого добавить
                    </p>
                  ) : (
                    <ul className="space-y-1">
                      {addCandidates.map((u) => {
                        const sel = pickIds.has(u.id);
                        const label = u.displayName?.trim() || u.username;
                        return (
                          <li key={u.id}>
                            <button
                              type="button"
                              onClick={() => togglePick(u.id)}
                              className={`flex w-full items-center gap-2 rounded-lg px-2 py-2 text-left text-sm ${
                                sel ? 'bg-tg-mine/80 dark:bg-slate-800/60' : 'hover:bg-tg-hover'
                              }`}
                            >
                              <span
                                className={`flex h-5 w-5 shrink-0 items-center justify-center rounded border-2 ${
                                  sel
                                    ? 'border-tg-accent bg-tg-accent text-white'
                                    : 'border-tg-border'
                                }`}
                              >
                                {sel ? (
                                  <IconCheck className="h-3 w-3" />
                                ) : null}
                              </span>
                              <UserAvatar
                                username={label}
                                avatarUrl={u.avatarUrl}
                                size="sm"
                              />
                              <span className="truncate font-medium">
                                {label}
                              </span>
                              <span className="truncate text-xs text-tg-muted">
                                @{u.username}
                              </span>
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  )}
                  {pickIds.size > 0 ? (
                    <button
                      type="button"
                      disabled={saving}
                      onClick={() => void submitAdd()}
                      className="mt-2 w-full rounded-xl bg-tg-accent py-2 text-sm font-semibold text-white disabled:opacity-50"
                    >
                      Добавить выбранных ({pickIds.size})
                    </button>
                  ) : null}
                </div>
              ) : null}
            </div>
          ) : (
            <p className="mt-1 text-sm text-tg-muted">{chat.name}</p>
          )}
          {chat.type === 'channel' ? (
            <p className="mt-2 text-xs font-medium text-tg-accent">
              {ruSubscribers(count)}
            </p>
          ) : (
            <p className="mt-2 text-xs text-tg-muted">{ruMembers(count)}</p>
          )}
          {err ? (
            <p className="mt-2 text-sm text-red-500 dark:text-red-400">{err}</p>
          ) : null}
        </div>
        <ul className="scrollbar-thin max-h-[45vh] overflow-y-auto py-2">
          {parts.map((p) => {
            const online = onlineUserIds.includes(p.id);
            const isSelf = p.id === selfId;
            const isChannelOwner =
              chat.type === 'channel' && p.id === chat.channelOwnerId;
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
                      {isChannelOwner ? (
                        <span className="ml-2 text-xs font-medium text-tg-accent">
                          владелец
                        </span>
                      ) : null}
                    </p>
                    <p className="text-xs text-tg-muted">
                      @{p.username}
                      {online ? (
                        <span className="ml-2 text-emerald-600 dark:text-emerald-400">
                          · в сети
                        </span>
                      ) : (
                        <span className="ml-2">· не в сети</span>
                      )}
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
