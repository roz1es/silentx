import { useState } from 'react';
import { useMessenger } from '@/contexts/MessengerContext';

type Props = {
  open: boolean;
  onClose: () => void;
};

export function NewChatModal({ open, onClose }: Props) {
  const { createDirect, createGroup } = useMessenger();
  const [tab, setTab] = useState<'direct' | 'group'>('direct');
  const [username, setUsername] = useState('');
  const [groupName, setGroupName] = useState('');
  const [members, setMembers] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  if (!open) return null;

  const submit = async () => {
    setError(null);
    setLoading(true);
    try {
      if (tab === 'direct') {
        if (username.trim().length < 2) {
          setError('Введите имя пользователя');
          return;
        }
        await createDirect(username.trim());
      } else {
        if (groupName.trim().length < 2) {
          setError('Введите название группы');
          return;
        }
        const parts = members
          .split(/[,\s]+/)
          .map((s) => s.trim())
          .filter(Boolean);
        await createGroup(groupName.trim(), parts);
      }
      setUsername('');
      setGroupName('');
      setMembers('');
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Ошибка');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="w-full max-w-md rounded-2xl border border-tg-border bg-tg-panel p-5 shadow-2xl">
        <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
          Новый чат
        </h2>
        <div className="mt-4 flex gap-2 rounded-xl bg-tg-hover p-1">
          <button
            type="button"
            className={`flex-1 rounded-lg py-2 text-sm font-medium ${
              tab === 'direct'
                ? 'bg-tg-panel shadow-sm'
                : 'text-tg-muted'
            }`}
            onClick={() => setTab('direct')}
          >
            Личный
          </button>
          <button
            type="button"
            className={`flex-1 rounded-lg py-2 text-sm font-medium ${
              tab === 'group'
                ? 'bg-tg-panel shadow-sm'
                : 'text-tg-muted'
            }`}
            onClick={() => setTab('group')}
          >
            Группа
          </button>
        </div>
        {tab === 'direct' ? (
          <label className="mt-4 block text-sm">
            <span className="text-tg-muted">Имя пользователя</span>
            <input
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="mt-1 w-full rounded-xl border border-tg-border bg-white px-3 py-2 text-slate-900 outline-none focus:ring-2 focus:ring-tg-accent/40 dark:bg-slate-900/40 dark:text-slate-100"
              placeholder="alice"
            />
          </label>
        ) : (
          <>
            <label className="mt-4 block text-sm">
              <span className="text-tg-muted">Название группы</span>
              <input
                value={groupName}
                onChange={(e) => setGroupName(e.target.value)}
                className="mt-1 w-full rounded-xl border border-tg-border bg-white px-3 py-2 text-slate-900 outline-none focus:ring-2 focus:ring-tg-accent/40 dark:bg-slate-900/40 dark:text-slate-100"
                placeholder="Команда"
              />
            </label>
            <label className="mt-3 block text-sm">
              <span className="text-tg-muted">Участники (через запятую)</span>
              <input
                value={members}
                onChange={(e) => setMembers(e.target.value)}
                className="mt-1 w-full rounded-xl border border-tg-border bg-white px-3 py-2 text-slate-900 outline-none focus:ring-2 focus:ring-tg-accent/40 dark:bg-slate-900/40 dark:text-slate-100"
                placeholder="bob, alice"
              />
            </label>
          </>
        )}
        {error ? (
          <p className="mt-3 text-sm text-red-500 dark:text-red-400">{error}</p>
        ) : null}
        <div className="mt-6 flex justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl px-4 py-2 text-sm font-medium text-tg-muted hover:bg-tg-hover"
          >
            Отмена
          </button>
          <button
            type="button"
            disabled={loading}
            onClick={() => void submit()}
            className="rounded-xl bg-tg-accent px-4 py-2 text-sm font-semibold text-white shadow hover:brightness-105 disabled:opacity-50"
          >
            {loading ? '…' : 'Создать'}
          </button>
        </div>
      </div>
    </div>
  );
}
