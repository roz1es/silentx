import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import * as api from '@/lib/api';
import { BirthDateFields } from '@/components/BirthDateFields';
import { IconCheck, IconBell, IconBellOff, IconClose } from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { AvatarEditorModal } from '@/components/AvatarEditorModal';
import { participantLabel } from '@/lib/userDisplay';
import { usePushNotifications } from '@/hooks/usePushNotifications';

const MAX_AVATAR_BYTES = 6 * 1024 * 1024;
const WINDOWS_INSTALLER_URL = '/desktop/windows/BrenksChatSetup-latest.exe';
const MACOS_INSTALLER_URL = '/desktop/macos/BrenksChat-macOS-latest.dmg';

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

function formatSessionDate(ts: number): string {
  return new Intl.DateTimeFormat('ru', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(ts));
}

function sessionTimeLeft(expiresAt: number): string {
  const ms = Math.max(0, expiresAt - Date.now());
  const days = Math.floor(ms / 86_400_000);
  if (days > 0) return `${days} дн.`;
  const hours = Math.floor(ms / 3_600_000);
  if (hours > 0) return `${hours} ч.`;
  const minutes = Math.max(1, Math.floor(ms / 60_000));
  return `${minutes} мин.`;
}

export function ProfileModal({ open, onClose }: Props) {
  const { user, updateProfile, confirmEmailBind, logout } = useAuth();
  const { refreshChats } = useMessenger();
  const { status, isSubscribed, loading: pushLoading, subscribe, unsubscribe } = usePushNotifications();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [displayName, setDisplayName] = useState('');
  const [bio, setBio] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [emailCode, setEmailCode] = useState('');
  const [emailTicket, setEmailTicket] = useState<string | null>(null);
  const [emailNotice, setEmailNotice] = useState<string | null>(null);
  const [birthDate, setBirthDate] = useState('');
  const [showOnline, setShowOnline] = useState(true);
  const [allowCalls, setAllowCalls] = useState(true);
  const [showEmail, setShowEmail] = useState(false);
  const [copied, setCopied] = useState(false);
  const [profileLinkCopied, setProfileLinkCopied] = useState(false);
  const [qrDataUrl, setQrDataUrl] = useState('');
  const [logoutConfirmOpen, setLogoutConfirmOpen] = useState(false);
  const [avatarDraft, setAvatarDraft] = useState<string | null>(null);
  const [sessions, setSessions] = useState<api.AuthSessionInfo[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);
  const [sessionBusyId, setSessionBusyId] = useState<string | null>(null);
  const [sessionsNotice, setSessionsNotice] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open && user) {
      setDisplayName(user.displayName ?? '');
      setBio(user.bio ?? '');
      setPhone(user.phone ?? '');
      setEmail(user.email ?? '');
      setEmailCode('');
      setEmailTicket(null);
      setEmailNotice(null);
      setBirthDate(user.birthDate ?? '');
      setShowOnline(user.privacy?.showOnline !== false);
      setAllowCalls(user.privacy?.allowCalls !== false);
      setShowEmail(user.privacy?.showEmail === true);
      setLogoutConfirmOpen(false);
      setAvatarDraft(null);
      setSessionsNotice(null);
      setProfileLinkCopied(false);
      setQrDataUrl('');
      setError(null);
      const profileUrl = `${window.location.origin}/u/${encodeURIComponent(
        user.username
      )}`;
      QRCode.toDataURL(profileUrl, {
        margin: 1,
        width: 220,
        color: {
          dark: '#111827',
          light: '#ffffff',
        },
      })
        .then(setQrDataUrl)
        .catch(() => setQrDataUrl(''));
      setSessionsLoading(true);
      api
        .fetchAuthSessions()
        .then(({ sessions }) => setSessions(sessions))
        .catch(() => setSessions([]))
        .finally(() => setSessionsLoading(false));
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
      setError('Фото должно быть до 6 МБ');
      return;
    }
    setError(null);
    try {
      const dataUrl = await readFileAsDataUrl(f);
      setAvatarDraft(dataUrl);
      if (inputRef.current) inputRef.current.value = '';
    } catch {
      setError('Не удалось открыть фото');
    }
  };

  const saveAvatar = async (dataUrl: string) => {
    setError(null);
    setLoading(true);
    try {
      await updateProfile({ avatarUrl: dataUrl });
      await refreshChats().catch(() => {});
      setAvatarDraft(null);
    } catch {
      throw new Error('Не удалось сохранить фото');
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
        privacy: {
          showOnline,
          allowCalls,
          showEmail,
        },
      });
      await refreshChats().catch(() => {});
    } catch {
      setError('Не удалось сохранить');
    } finally {
      setLoading(false);
    }
  };

  const requestEmailCode = async () => {
    setError(null);
    setEmailNotice(null);
    setLoading(true);
    try {
      const result = await api.requestEmailBind(email);
      setEmailTicket(result.ticket);
      setEmailCode('');
      setEmailNotice(`Код отправлен на ${result.emailMasked}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось отправить код');
    } finally {
      setLoading(false);
    }
  };

  const confirmEmailCode = async () => {
    if (!emailTicket) return;
    setError(null);
    setLoading(true);
    try {
      await confirmEmailBind(emailTicket, emailCode);
      setEmailTicket(null);
      setEmailCode('');
      setEmailNotice('Почта подтверждена и привязана к аккаунту');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось подтвердить код');
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

  const copyProfileLink = async () => {
    const origin = window.location.origin;
    const url = `${origin}/u/${encodeURIComponent(user.username)}`;
    try {
      await navigator.clipboard.writeText(url);
      setProfileLinkCopied(true);
      setTimeout(() => setProfileLinkCopied(false), 2000);
    } catch {
      setError('Не удалось скопировать ссылку');
    }
  };

  const shareProfile = async () => {
    const url = `${window.location.origin}/u/${encodeURIComponent(user.username)}`;
    try {
      if (navigator.share) {
        await navigator.share({
          title: `Профиль ${label} в БренксЧат`,
          text: `@${user.username}`,
          url,
        });
        return;
      }
      await navigator.clipboard.writeText(url);
      setProfileLinkCopied(true);
      setTimeout(() => setProfileLinkCopied(false), 2000);
    } catch {
      /* пользователь мог закрыть системное окно */
    }
  };

  const refreshSessions = async () => {
    setSessionsLoading(true);
    try {
      const result = await api.fetchAuthSessions();
      setSessions(result.sessions);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось загрузить сеансы');
    } finally {
      setSessionsLoading(false);
    }
  };

  const revokeSession = async (sessionId: string) => {
    setSessionBusyId(sessionId);
    setSessionsNotice(null);
    try {
      await api.revokeAuthSession(sessionId);
      setSessions((prev) => prev.filter((session) => session.id !== sessionId));
      setSessionsNotice('Сеанс завершён');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось завершить сеанс');
    } finally {
      setSessionBusyId(null);
    }
  };

  const revokeOtherSessions = async () => {
    setSessionBusyId('all');
    setSessionsNotice(null);
    try {
      const result = await api.revokeOtherAuthSessions();
      setSessions((prev) => prev.filter((session) => session.current));
      setSessionsNotice(
        result.revoked > 0
          ? `Завершено сеансов: ${result.revoked}`
          : 'Других активных сеансов нет'
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Не удалось завершить сеансы');
    } finally {
      setSessionBusyId(null);
    }
  };

  return (
    <div
      className="brenks-modal-backdrop fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4"
      role="dialog"
      aria-modal="true"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="brenks-modal-panel flex max-h-[min(92dvh,780px)] w-full max-w-md flex-col overflow-hidden rounded-[1.7rem]">
        <div className="flex shrink-0 items-center justify-between gap-3 border-b border-tg-border/60 px-5 py-4">
          <div>
            <h2 className="text-xl font-semibold tracking-normal text-slate-900 dark:text-slate-100">
              Мой профиль
            </h2>
            <p className="mt-1 text-sm text-tg-muted">
              Аккаунт, приватность и уведомления
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="brenks-profile-button flex h-10 w-10 shrink-0 items-center justify-center rounded-full"
            title="Закрыть"
          >
            <IconClose className="h-4 w-4" />
          </button>
        </div>

        <div className="brenks-modal-scroll scrollbar-thin tg-soft-scrollbar min-h-0 flex-1 overflow-y-auto px-5 pb-5">
          <div className="flex flex-col gap-4 pb-2 pt-5">
            <section className="brenks-profile-card rounded-[1.45rem] p-4 text-center">
              <UserAvatar
                username={label}
                avatarUrl={user.avatarUrl}
                size="lg"
                className="mx-auto ring-4 ring-white/55 shadow-[0_16px_38px_rgba(15,23,42,0.14)] dark:ring-white/10"
              />
              <p className="mt-3 text-xl font-semibold text-slate-900 dark:text-slate-100">
                {label}
              </p>
              <p className="text-sm text-tg-muted">@{user.username}</p>
              <div className="mt-3 flex flex-wrap justify-center gap-2">
                <button
                  type="button"
                  onClick={() => void copyProfileLink()}
                  className="brenks-profile-button rounded-2xl px-3 py-2 text-xs font-semibold"
                >
                  {profileLinkCopied ? 'Ссылка скопирована' : 'Ссылка профиля'}
                </button>
                <button
                  type="button"
                  onClick={() => void shareProfile()}
                  className="brenks-profile-button rounded-2xl px-3 py-2 text-xs font-semibold"
                >
                  Поделиться
                </button>
                <button
                  type="button"
                  onClick={() => {
                    void navigator.clipboard.writeText(`@${user.username}`);
                  }}
                  className="brenks-profile-button rounded-2xl px-3 py-2 text-xs font-semibold"
                >
                  @{user.username}
                </button>
              </div>
              {qrDataUrl ? (
                <div className="mx-auto mt-4 w-full max-w-[15rem] rounded-[1.35rem] border border-white/45 bg-white/48 p-3 shadow-inner backdrop-blur-xl dark:border-white/10 dark:bg-white/[0.055]">
                  <img
                    src={qrDataUrl}
                    alt="QR-код профиля"
                    className="mx-auto h-36 w-36 rounded-2xl"
                  />
                  <p className="mt-2 text-center text-xs font-medium text-tg-muted">
                    QR профиля @{user.username}
                  </p>
                </div>
              ) : null}
              <div className="mt-4 flex items-center justify-between gap-3 rounded-2xl border border-white/45 bg-white/34 px-4 py-3 text-left backdrop-blur-xl dark:border-white/10 dark:bg-white/[0.045]">
                <div className="min-w-0">
                  <p className="text-xs text-tg-muted">Почта для входа</p>
                  <p className="mt-0.5 truncate text-sm font-semibold text-slate-800 dark:text-slate-100">
                    {user.emailVerified && user.email ? user.email : 'Не привязана'}
                  </p>
                </div>
                <span
                  className={`shrink-0 rounded-full px-2.5 py-1 text-[10px] font-semibold ${
                    user.emailVerified
                      ? 'bg-emerald-100/80 text-emerald-700 dark:bg-emerald-400/10 dark:text-emerald-300'
                      : 'bg-amber-100/85 text-amber-700 dark:bg-amber-400/10 dark:text-amber-300'
                  }`}
                >
                  {user.emailVerified ? 'OK' : 'Нужно'}
                </span>
              </div>
            </section>

            <section className="brenks-profile-card rounded-[1.35rem] p-4">
              <input
                ref={inputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => void onPick(e.target.files)}
              />
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  disabled={loading}
                  onClick={() => inputRef.current?.click()}
                  className="brenks-profile-button brenks-profile-button--primary rounded-2xl px-4 py-2 text-sm font-semibold disabled:opacity-50"
                >
                  {loading ? '…' : 'Сменить фото'}
                </button>
                {user.avatarUrl ? (
                  <button
                    type="button"
                    disabled={loading}
                    onClick={() => void removeAvatar()}
                    className="brenks-profile-button rounded-2xl px-4 py-2 text-sm font-semibold disabled:opacity-50"
                  >
                    Убрать фото
                  </button>
                ) : null}
              </div>
            </section>

            {user.isAdmin ? (
              <section className="brenks-profile-card rounded-[1.35rem] p-4">
                <label className="text-xs font-medium uppercase tracking-wide text-tg-muted">
                  Ваш ID
                </label>
                <div className="mt-2 flex gap-2">
                  <code className="min-w-0 flex-1 truncate rounded-2xl border border-white/45 bg-white/34 px-3 py-2 text-[11px] text-slate-800 backdrop-blur-xl dark:border-white/10 dark:bg-white/[0.045] dark:text-slate-200">
                    {user.id}
                  </code>
                  <button
                    type="button"
                    onClick={() => void copyId()}
                    className="brenks-profile-button brenks-profile-button--primary flex shrink-0 items-center justify-center rounded-2xl px-3 py-2 text-xs font-semibold"
                  >
                    {copied ? <IconCheck className="h-4 w-4" /> : 'Копир.'}
                  </button>
                </div>
              </section>
            ) : null}

            <section className="brenks-profile-card space-y-3 rounded-[1.35rem] p-4">
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
                  className="brenks-profile-input mt-1 w-full rounded-2xl px-3 py-2 text-sm outline-none"
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
                  className="brenks-profile-input mt-1 w-full resize-none rounded-2xl px-3 py-2 text-sm outline-none"
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
                  className="brenks-profile-input mt-1 w-full rounded-2xl px-3 py-2 text-sm outline-none"
                />
              </div>
            </section>

            <section className="brenks-profile-card rounded-[1.35rem] p-4">
              <label className="text-xs text-tg-muted" htmlFor="pf-email">
                Почта
              </label>
              <div className="mt-1 flex gap-2">
                <input
                  id="pf-email"
                  type="email"
                  value={email}
                  onChange={(e) => {
                    setEmail(e.target.value);
                    setEmailTicket(null);
                    setEmailCode('');
                    setEmailNotice(null);
                  }}
                  placeholder="mail@example.com"
                  className="brenks-profile-input min-w-0 flex-1 rounded-2xl px-3 py-2 text-sm outline-none"
                />
                <button
                  type="button"
                  disabled={loading || email.trim().length === 0}
                  onClick={() => void requestEmailCode()}
                  className="brenks-profile-button shrink-0 rounded-2xl px-3 py-2 text-xs font-semibold disabled:opacity-50"
                >
                  Код
                </button>
              </div>
              {emailTicket ? (
                <div className="mt-2 flex gap-2">
                  <input
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    value={emailCode}
                    onChange={(e) => setEmailCode(e.target.value)}
                    placeholder="123456"
                    className="brenks-profile-input min-w-0 flex-1 rounded-2xl px-3 py-2 text-sm outline-none"
                  />
                  <button
                    type="button"
                    disabled={loading || emailCode.trim().length < 4}
                    onClick={() => void confirmEmailCode()}
                    className="brenks-profile-button brenks-profile-button--primary shrink-0 rounded-2xl px-3 py-2 text-xs font-semibold disabled:opacity-50"
                  >
                    OK
                  </button>
                </div>
              ) : null}
              <p className="mt-2 text-xs text-tg-muted">
                После подтверждения вход и сброс пароля будут работать через эту почту.
              </p>
              {emailNotice ? (
                <p className="mt-2 text-xs font-medium text-emerald-600 dark:text-emerald-300">
                  {emailNotice}
                </p>
              ) : null}
            </section>

            <section className="brenks-profile-card rounded-[1.35rem] p-4">
              <BirthDateFields
                value={birthDate}
                onChange={setBirthDate}
                disabled={loading}
              />
            </section>

            <section className="brenks-profile-card rounded-[1.35rem] p-4">
              <p className="mb-2 text-sm font-semibold text-slate-800 dark:text-slate-100">
                Приватность
              </p>
              <PrivacyToggle
                label="Показывать онлайн"
                checked={showOnline}
                onChange={setShowOnline}
              />
              <PrivacyToggle
                label="Разрешить звонки"
                checked={allowCalls}
                onChange={setAllowCalls}
              />
              <PrivacyToggle
                label="Показывать почту в профиле"
                checked={showEmail}
                onChange={setShowEmail}
              />
            </section>

            <section className="brenks-profile-card rounded-[1.35rem] p-4">
              <div className="flex items-center justify-between gap-3">
                <div className="flex min-w-0 items-center gap-3">
                  {isSubscribed ? (
                    <IconBell className="h-5 w-5 shrink-0 text-emerald-500" />
                  ) : (
                    <IconBellOff className="h-5 w-5 shrink-0 text-tg-muted" />
                  )}
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-slate-800 dark:text-slate-100">
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
                    className="brenks-profile-switch relative h-7 w-12 shrink-0 rounded-full transition-colors disabled:opacity-50"
                    data-checked={isSubscribed}
                  >
                    <span
                      className={`absolute left-1 top-1 h-5 w-5 rounded-full bg-white shadow transition-transform ${
                        isSubscribed ? 'translate-x-5' : 'translate-x-0'
                      }`}
                    />
                  </button>
                ) : null}
              </div>
            </section>

            <button
              type="button"
              disabled={loading}
              onClick={() => void saveText()}
              className="brenks-profile-button brenks-profile-button--primary w-full rounded-2xl py-3 text-sm font-semibold disabled:opacity-50"
            >
              {loading ? 'Сохранение…' : 'Сохранить профиль'}
            </button>

            <section className="brenks-profile-card rounded-[1.35rem] p-4">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-sm font-semibold text-slate-800 dark:text-slate-100">
                    Активные сеансы
                  </p>
                  <p className="mt-0.5 text-xs text-tg-muted">
                    Управляйте входами на других устройствах
                  </p>
                </div>
                <button
                  type="button"
                  disabled={sessionsLoading}
                  onClick={() => void refreshSessions()}
                  className="brenks-profile-button shrink-0 rounded-2xl px-3 py-2 text-xs font-semibold disabled:opacity-50"
                >
                  Обновить
                </button>
              </div>
              <div className="mt-3 space-y-2">
                {sessionsLoading ? (
                  <p className="rounded-2xl border border-white/45 bg-white/30 px-3 py-3 text-sm text-tg-muted backdrop-blur-xl dark:border-white/10 dark:bg-white/[0.04]">
                    Загружаю сеансы…
                  </p>
                ) : sessions.length > 0 ? (
                  sessions.map((session) => (
                    <div
                      key={session.id}
                      className="rounded-2xl border border-white/45 bg-white/34 px-3 py-3 backdrop-blur-xl dark:border-white/10 dark:bg-white/[0.045]"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="text-sm font-semibold text-slate-800 dark:text-slate-100">
                            {session.current ? 'Это устройство' : 'Другое устройство'}
                          </p>
                          <p className="mt-0.5 text-xs text-tg-muted">
                            Вход: {formatSessionDate(session.createdAt)}
                          </p>
                          <p className="mt-0.5 text-xs text-tg-muted">
                            Осталось: {sessionTimeLeft(session.expiresAt)}
                            {session.remembered ? ' · запомнено' : ''}
                          </p>
                        </div>
                        {session.current ? (
                          <span className="rounded-full bg-emerald-100/80 px-2.5 py-1 text-[10px] font-semibold text-emerald-700 dark:bg-emerald-400/10 dark:text-emerald-300">
                            сейчас
                          </span>
                        ) : (
                          <button
                            type="button"
                            disabled={sessionBusyId === session.id}
                            onClick={() => void revokeSession(session.id)}
                            className="brenks-profile-button brenks-profile-button--danger shrink-0 rounded-2xl px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
                          >
                            Завершить
                          </button>
                        )}
                      </div>
                    </div>
                  ))
                ) : (
                  <p className="rounded-2xl border border-white/45 bg-white/30 px-3 py-3 text-sm text-tg-muted backdrop-blur-xl dark:border-white/10 dark:bg-white/[0.04]">
                    Активных сеансов не найдено
                  </p>
                )}
              </div>
              <button
                type="button"
                disabled={
                  sessionBusyId === 'all' ||
                  sessions.filter((session) => !session.current).length === 0
                }
                onClick={() => void revokeOtherSessions()}
                className="brenks-profile-button mt-3 w-full rounded-2xl py-2.5 text-sm font-semibold disabled:opacity-50"
              >
                {sessionBusyId === 'all'
                  ? 'Завершаю…'
                  : 'Завершить все остальные'}
              </button>
              {sessionsNotice ? (
                <p className="mt-2 text-center text-xs font-medium text-emerald-600 dark:text-emerald-300">
                  {sessionsNotice}
                </p>
              ) : null}
            </section>

            <section className="brenks-profile-card rounded-[1.35rem] p-4">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-sm font-semibold text-slate-800 dark:text-slate-100">
                    Приложение БренксЧат
                  </p>
                  <p className="mt-0.5 text-xs text-tg-muted">
                    Установщик для компьютера и будущие версии
                  </p>
                </div>
                <span className="rounded-full border border-white/50 bg-white/45 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-tg-muted backdrop-blur-xl dark:border-white/10 dark:bg-white/[0.05]">
                  Desktop
                </span>
              </div>

              <a
                href={WINDOWS_INSTALLER_URL}
                download
                className="brenks-profile-button brenks-profile-button--primary mt-3 flex w-full items-center justify-center gap-2 rounded-2xl py-3 text-sm font-semibold no-underline"
              >
                <svg
                  viewBox="0 0 24 24"
                  aria-hidden
                  className="h-4 w-4 fill-current"
                >
                  <path d="M3.5 5.2 10.6 4v7.1H3.5V5.2ZM12 3.8 20.5 2.4v8.7H12V3.8ZM3.5 12.5h7.1V20l-7.1-1.2v-6.3ZM12 12.5h8.5v9.1L12 20.2v-7.7Z" />
                </svg>
                Установить на Windows
              </a>

              <a
                href={MACOS_INSTALLER_URL}
                download
                className="brenks-profile-button mt-2 flex w-full items-center justify-center gap-2 rounded-2xl py-3 text-sm font-semibold no-underline"
              >
                <svg
                  viewBox="0 0 24 24"
                  aria-hidden
                  className="h-4 w-4 fill-current"
                >
                  <path d="M15.9 2.3c.2 1.5-.4 2.9-1.3 3.9-.9.9-2.2 1.7-3.6 1.6-.2-1.4.5-2.9 1.3-3.8.9-1 2.4-1.7 3.6-1.7Zm4.2 15.3c-.7 1.5-1.1 2.1-2 3.4-1.3 1.8-3.1 1.9-3.9 1.9-.9 0-1.8-.6-2.9-.6-1.1 0-2.1.6-3 .6-.9 0-2.5-.1-3.8-1.8C1.9 17.6 1.6 12.6 3.3 9.9c1.2-1.9 3-3 4.8-3 1 0 2 .6 2.9.6.9 0 2.5-.8 4.2-.7.7 0 2.8.3 4.1 2.2-3.6 2-3 7 .8 8.6Z" />
                </svg>
                Установить на macOS
              </a>

              <div className="mt-2 grid grid-cols-2 gap-2">
                {['Android', 'iPhone'].map((platform) => (
                  <button
                    key={platform}
                    type="button"
                    disabled
                    className="rounded-2xl border border-white/10 bg-slate-900/80 px-2 py-2 text-[11px] font-semibold text-slate-300 opacity-85 shadow-inner dark:bg-black/35"
                  >
                    {platform}
                    <span className="mt-0.5 block text-[10px] font-medium text-slate-400">
                      в разработке
                    </span>
                  </button>
                ))}
              </div>
            </section>

            <section className="brenks-profile-card rounded-[1.35rem] p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className="text-sm font-semibold text-slate-800 dark:text-slate-100">
                    Аккаунт
                  </p>
                  <p className="mt-0.5 text-xs text-tg-muted">
                    Завершить текущую сессию
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => setLogoutConfirmOpen(true)}
                  className="brenks-profile-button brenks-profile-button--danger shrink-0 rounded-2xl px-4 py-2 text-xs font-semibold"
                >
                  Выйти
                </button>
              </div>
              {logoutConfirmOpen ? (
                <div className="mt-3 rounded-2xl border border-red-200/60 bg-white/42 p-3 backdrop-blur-xl dark:border-red-500/20 dark:bg-white/[0.04]">
                  <p className="text-sm font-medium text-slate-800 dark:text-slate-100">
                    Точно выйти?
                  </p>
                  <div className="mt-3 grid grid-cols-2 gap-2">
                    <button
                      type="button"
                      onClick={() => {
                        setLogoutConfirmOpen(false);
                        onClose();
                        void logout();
                      }}
                      className="brenks-profile-button brenks-profile-button--danger rounded-2xl py-2 text-sm font-semibold"
                    >
                      Да
                    </button>
                    <button
                      type="button"
                      onClick={() => setLogoutConfirmOpen(false)}
                      className="brenks-profile-button rounded-2xl py-2 text-sm font-semibold"
                    >
                      Отмена
                    </button>
                  </div>
                </div>
              ) : null}
            </section>

            {error ? (
              <p className="rounded-2xl border border-red-300/45 bg-red-50/55 px-3 py-2 text-center text-sm text-red-600 backdrop-blur-xl dark:border-red-400/20 dark:bg-red-500/10 dark:text-red-300">
                {error}
              </p>
            ) : null}
          </div>
        </div>

        <div className="shrink-0 border-t border-tg-border/60 bg-tg-hover/20 px-5 py-4 backdrop-blur-xl">
          <button
            type="button"
            onClick={onClose}
            className="brenks-profile-button w-full rounded-2xl py-2.5 text-sm font-semibold"
          >
            Закрыть
          </button>
        </div>
      </div>
      <AvatarEditorModal
        open={Boolean(avatarDraft)}
        src={avatarDraft}
        saving={loading}
        onCancel={() => setAvatarDraft(null)}
        onSave={saveAvatar}
      />
    </div>
  );
}

function PrivacyToggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="flex cursor-pointer items-center justify-between gap-3 py-2 text-sm text-slate-700 dark:text-slate-200">
      <span>{label}</span>
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="sr-only"
      />
      <span
        className="brenks-profile-switch relative h-7 w-12 shrink-0 rounded-full transition-colors"
        data-checked={checked}
      >
        <span
          className={`absolute left-1 top-1 h-5 w-5 rounded-full bg-white shadow transition-transform ${
            checked ? 'translate-x-5' : 'translate-x-0'
          }`}
        />
      </span>
    </label>
  );
}
