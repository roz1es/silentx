import { useEffect, useRef, useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import { BirthDateFields } from '@/components/BirthDateFields';
import { IconCheck, IconBell, IconBellOff } from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { participantLabel } from '@/lib/userDisplay';
import { usePushNotifications } from '@/hooks/usePushNotifications';

const MAX_AVATAR_BYTES = 600 * 1024;

type Props = {
  open: boolean;
  onClose: () => void;
};

function readFileAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(new Error('read'));
    r.readAsDataURL(file);
  });
}

export function ProfileModal({ open, onClose }: Props) {
  const { user, updateProfile } = useAuth();
  const { refreshChats } = useMessenger();
  const { status, isSubscribed, loading: pushLoading, subscribe, unsubscribe } = usePushNotifications();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [displayName, setDisplayName] = useState('');
  const [bio, setBio] = useState('');
  const [phone, setPhone] = useState('');
  const [birthDate, setBirthDate] = useState('');
  const [copied, setCopied] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open && user) {
      setDisplayName(user.displayName ?? '');
      setBio(user.bio ?? '');
      setPhone(user.phone ?? '');
      setBirthDate(user.birthDate ?? '');
      setError(null);
    }
  }, [open, user]);

  if (!open || !user) return null;

  const label = participantLabel(user);

  const onPick = async (files: FileList | null) => {
    const f = files?.[0];
    if (!f || !f.type.startsWith('image/')) {
      setError('Выберите изображение');
      return;
    }
    if (f.size > MAX_AVATAR_BYTES) {
      setError('До 600 КБ');
      return;
    }
    setError(null);
    setLoading(true);
    try {
      const dataUrl = await readFileAsDataUrl(f);
      await updateProfile({ avatarUrl: dataUrl });
      await refreshChats().catch(() => {});
      onClose();
    } catch {
      setError('Не удалось сохранить');
    } finally {
      setLoading(false);
    }
  };

  const removeAvatar = async () => {
    setLoading(true);
    try {
      await updateProfile({ avatarUrl: null });
      await refreshChats().catch(() => {});
      onClose();
    } finally {
      setLoading(false);
    }
  };

  const saveText = async () => {
    setError(null);
    setLoading(true);
    try {
      await updateProfile({
        displayName: displayName.trim() || null,
        bio: bio.trim() || null,
        phone: phone.trim() || null,
        birthDate: birthDate.trim() || null,
      });
      await refreshChats().catch(() => {});
    } catch {
      setError('Не удалось сохранить');
    } finally {
      setLoading(false);
    }
  };

  const copyId = async () => {
    try {
      await navigator.clipboard.writeText(user.id);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setError('Не удалось скопировать ID');
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
      <div className="scrollbar-thin tg-soft-scrollbar max-h-[90vh] w-full max-w-sm overflow-y-auto rounded-2xl border border-tg-border bg-tg-panel p-6 shadow-2xl">
        <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
          Мой профиль
        </h2>
        <div className="mt-6 flex flex-col items-center gap-4">
          <UserAvatar
            username={label}
            avatarUrl={user.avatarUrl}
            size="lg"
          />
          <p className="text-sm text-tg-muted">
            Логин: <span className="font-medium text-slate-800 dark:text-slate-200">{user.username}</span>
          </p>
          {user.isAdmin ? (
            <div className="flex w-full max-w-xs flex-col gap-1">
              <label className="text-xs text-tg-muted">Ваш ID</label>
              <div className="flex gap-2">
                <code className="min-w-0 flex-1 truncate rounded-lg bg-tg-hover px-2 py-1.5 text-[11px] text-slate-800 dark:text-slate-200">
                  {user.id}
                </code>
                <button
                  type="button"
                  onClick={() => void copyId()}
                  className="flex shrink-0 items-center justify-center rounded-lg bg-tg-accent px-3 py-1.5 text-xs font-semibold text-white"
                >
                  {copied ? (
                    <IconCheck className="h-4 w-4" />
                  ) : (
                    'Копир.'
                  )}
                </button>
              </div>
            </div>
          ) : null}
          <input
            ref={inputRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={(e) => void onPick(e.target.files)}
          />
          <div className="flex flex-wrap justify-center gap-2">
            <button
              type="button"
              disabled={loading}
              onClick={() => inputRef.current?.click()}
              className="rounded-xl bg-tg-accent px-4 py-2 text-sm font-semibold text-white shadow hover:brightness-105 disabled:opacity-50"
            >
              {loading ? '…' : 'Сменить фото'}
            </button>
            {user.avatarUrl ? (
              <button
                type="button"
                disabled={loading}
                onClick={() => void removeAvatar()}
                className="rounded-xl bg-tg-hover px-4 py-2 text-sm text-slate-700 dark:text-slate-200"
              >
                Убрать фото
              </button>
            ) : null}
          </div>
          <div className="w-full space-y-3 text-left">
            <div>
              <label className="text-xs text-tg-muted" htmlFor="pf-display">
                Отображаемое имя
              </label>
              <input
                id="pf-display"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder={user.username}
                maxLength={64}
                className="mt-1 w-full rounded-xl border border-tg-border bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-tg-accent dark:bg-slate-900/40 dark:text-slate-100"
              />
            </div>
            <div>
              <label className="text-xs text-tg-muted" htmlFor="pf-bio">
                О себе
              </label>
              <textarea
                id="pf-bio"
                value={bio}
                onChange={(e) => setBio(e.target.value)}
                placeholder="Коротко о себе…"
                maxLength={500}
                rows={3}
                className="mt-1 w-full resize-none rounded-xl border border-tg-border bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-tg-accent dark:bg-slate-900/40 dark:text-slate-100"
              />
            </div>
            <div>
              <label className="text-xs text-tg-muted" htmlFor="pf-phone">
                Телефон
              </label>
              <input
                id="pf-phone"
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+7 …"
                maxLength={32}
                className="mt-1 w-full rounded-xl border border-tg-border bg-white px-3 py-2 text-sm text-slate-900 outline-none focus:border-tg-accent dark:bg-slate-900/40 dark:text-slate-100"
              />
            </div>
            <BirthDateFields
              value={birthDate}
              onChange={setBirthDate}
              disabled={loading}
            />
            
            {/* Push-уведомления */}
            <div className="rounded-xl border border-tg-border p-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  {isSubscribed ? (
                    <IconBell className="h-5 w-5 text-emerald-500" />
                  ) : (
                    <IconBellOff className="h-5 w-5 text-tg-muted" />
                  )}
                  <div>
                    <p className="text-sm font-medium text-slate-800 dark:text-slate-200">
                      Push-уведомления
                    </p>
                    <p className="text-xs text-tg-muted">
                      {status === 'unsupported' && 'Не поддерживаются'}
                      {status === 'denied' && 'Заблокированы в браузере'}
                      {status === 'granted' && (isSubscribed ? 'Включены' : 'Выключены')}
                      {status === 'default' && 'Нажмите для включения'}
                    </p>
                  </div>
                </div>
                {status !== 'unsupported' && status !== 'denied' ? (
                  <button
                    type="button"
                    disabled={pushLoading}
                    onClick={() => void (isSubscribed ? unsubscribe() : subscribe())}
                    className={`relative h-6 w-11 shrink-0 rounded-full transition-colors ${
                      isSubscribed ? 'bg-emerald-500' : 'bg-tg-border'
                    } disabled:opacity-50`}
                  >
                    <span
                      className={`absolute top-0.5 left-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform ${
                        isSubscribed ? 'translate-x-5' : 'translate-x-0'
                      }`}
                    />
                  </button>
                ) : null}
              </div>
            </div>
            
            <button
              type="button"
              disabled={loading}
              onClick={() => void saveText()}
              className="w-full rounded-xl bg-tg-hover py-2.5 text-sm font-semibold text-slate-800 dark:text-slate-100 disabled:opacity-50"
            >
              {loading ? 'Сохранение…' : 'Сохранить профиль'}
            </button>
          </div>
          {error ? (
            <p className="text-center text-sm text-red-500">{error}</p>
          ) : null}
        </div>
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
