import { useState } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { ThemeToggle } from '@/components/ThemeToggle';
import * as api from '@/lib/api';

type AuthMode = 'login' | 'register' | 'reset';
type PendingCode = {
  kind: AuthMode;
  ticket: string;
  emailMasked: string;
};

const windowsInstallerUrl = '/desktop/windows/BrenksChatSetup-latest.exe';
const macosInstallerUrl = '/desktop/macos/BrenksChat-macOS-latest.dmg';

type PlatformId = 'windows' | 'android' | 'macos' | 'iphone';

const downloadPlatforms: Array<{
  id: PlatformId;
  title: string;
  subtitle: string;
  href?: string;
}> = [
  {
    id: 'windows',
    title: 'Windows',
    subtitle: 'Скачать .exe',
    href: windowsInstallerUrl,
  },
  {
    id: 'android',
    title: 'Android',
    subtitle: 'в разработке',
  },
  {
    id: 'macos',
    title: 'macOS',
    subtitle: 'Скачать .dmg',
    href: macosInstallerUrl,
  },
  {
    id: 'iphone',
    title: 'iPhone',
    subtitle: 'в разработке',
  },
];

function PlatformIcon({ id }: { id: PlatformId }) {
  if (id === 'windows') {
    return (
      <svg viewBox="0 0 24 24" aria-hidden>
        <path d="M3.5 5.2 10.6 4v7.1H3.5V5.2ZM12 3.8 20.5 2.4v8.7H12V3.8ZM3.5 12.5h7.1V20l-7.1-1.2v-6.3ZM12 12.5h8.5v9.1L12 20.2v-7.7Z" />
      </svg>
    );
  }

  if (id === 'android') {
    return (
      <svg viewBox="0 0 24 24" aria-hidden>
        <path d="M8 4.5 6.7 2.2a.7.7 0 0 1 1.2-.7l1.4 2.4a7.6 7.6 0 0 1 5.4 0l1.4-2.4a.7.7 0 0 1 1.2.7L16 4.5A7.9 7.9 0 0 1 20 11v.4H4V11a7.9 7.9 0 0 1 4-6.5ZM7 13h10v6a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2v-6Zm-3 0h1.5v5H4a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1Zm14.5 0H20a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1h-1.5v-5ZM8.5 8.2a1 1 0 1 0 0-2 1 1 0 0 0 0 2Zm7 0a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" />
      </svg>
    );
  }

  if (id === 'iphone') {
    return (
      <svg viewBox="0 0 24 24" aria-hidden>
        <path d="M8.5 2.5h7A2.5 2.5 0 0 1 18 5v14a2.5 2.5 0 0 1-2.5 2.5h-7A2.5 2.5 0 0 1 6 19V5a2.5 2.5 0 0 1 2.5-2.5Zm.25 2A.75.75 0 0 0 8 5.25v13.5c0 .41.34.75.75.75h6.5c.41 0 .75-.34.75-.75V5.25a.75.75 0 0 0-.75-.75h-1.1l-.35.7a1 1 0 0 1-.9.55h-1.8a1 1 0 0 1-.9-.55l-.35-.7h-1.1Z" />
      </svg>
    );
  }

  return (
    <svg viewBox="0 0 24 24" aria-hidden>
      <path d="M15.9 2.3c.2 1.5-.4 2.9-1.3 3.9-.9.9-2.2 1.7-3.6 1.6-.2-1.4.5-2.9 1.3-3.8.9-1 2.4-1.7 3.6-1.7Zm4.2 15.3c-.7 1.5-1.1 2.1-2 3.4-1.3 1.8-3.1 1.9-3.9 1.9-.9 0-1.8-.6-2.9-.6-1.1 0-2.1.6-3 .6-.9 0-2.5-.1-3.8-1.8C1.9 17.6 1.6 12.6 3.3 9.9c1.2-1.9 3-3 4.8-3 1 0 2 .6 2.9.6.9 0 2.5-.8 4.2-.7.7 0 2.8.3 4.1 2.2-3.6 2-3 7 .8 8.6Z" />
    </svg>
  );
}

export function LoginPage() {
  const {
    user,
    loading,
    login,
    register,
    confirmLogin,
    confirmRegister,
  } = useAuth();
  const [mode, setMode] = useState<AuthMode>('login');
  const [pending, setPending] = useState<PendingCode | null>(null);
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [resetLogin, setResetLogin] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [code, setCode] = useState('');
  const [rememberMe, setRememberMe] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  if (user) return <Navigate to="/" replace />;

  const switchMode = (next: AuthMode) => {
    setMode(next);
    setPending(null);
    setCode('');
    setError(null);
    setNotice(null);
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setNotice(null);
    try {
      if (pending) {
        if (pending.kind === 'login') {
          await confirmLogin(pending.ticket, code, rememberMe, password);
          return;
        }
        if (pending.kind === 'register') {
          await confirmRegister(pending.ticket, code, password);
          return;
        }
        if (newPassword.length < 8) {
          setError('Пароль должен содержать минимум 8 символов');
          return;
        }
        await api.confirmPasswordReset(pending.ticket, code, newPassword);
        setPending(null);
        setMode('login');
        setPassword('');
        setNewPassword('');
        setCode('');
        setNotice('Пароль обновлён. Теперь можно войти.');
        return;
      }

      if (mode === 'login') {
        const result = await login(username, password, rememberMe);
        if ('emailCodeRequired' in result) {
          setPending({
            kind: 'login',
            ticket: result.ticket,
            emailMasked: result.emailMasked,
          });
          setCode('');
          setNotice(`Код отправлен на ${result.emailMasked}`);
        }
        return;
      }

      if (mode === 'register') {
        const result = await register(username, email, password);
        if ('emailVerificationRequired' in result) {
          setPending({
            kind: 'register',
            ticket: result.ticket,
            emailMasked: result.emailMasked,
          });
          setCode('');
          setNotice(`Код подтверждения отправлен на ${result.emailMasked}`);
        }
        return;
      }

      const result = await api.requestPasswordReset(resetLogin);
      if (result.ticket && result.emailMasked) {
        setPending({
          kind: 'reset',
          ticket: result.ticket,
          emailMasked: result.emailMasked,
        });
        setCode('');
        setNotice(`Код для сброса отправлен на ${result.emailMasked}`);
      } else {
        setNotice(result.message ?? 'Если почта привязана, код отправлен.');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  };

  const title = pending
    ? 'Введите код'
    : mode === 'login'
      ? 'С возвращением'
      : mode === 'register'
        ? 'Создаём профиль'
        : 'Сброс пароля';

  const subtitle = pending
    ? `Мы отправили письмо на ${pending.emailMasked}`
    : mode === 'login'
      ? 'Продолжайте переписку в БренксЧат'
      : mode === 'register'
        ? 'Почта нужна для входа и сброса пароля'
        : 'Укажите логин или почту аккаунта';

  return (
    <main className="login-page-shell animated-bg bg-[rgb(var(--tg-bg))] text-slate-900 dark:text-slate-100">
      <section className="login-window">
        <div className="mb-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="relative flex h-10 w-10 items-center justify-center overflow-hidden rounded-2xl border border-white/80 bg-white/80 shadow-[0_10px_24px_rgba(15,23,42,0.08)] backdrop-blur-xl dark:border-white/10 dark:bg-zinc-700/80 dark:shadow-black/20">
              <img
                src="/logo.svg"
                alt=""
                className="h-full w-full object-cover"
              />
              <span className="absolute -right-0.5 -top-0.5 h-3 w-3 rounded-full border-2 border-[rgb(var(--tg-bg))] bg-emerald-400 shadow-sm" />
            </div>
            <div>
              <p className="text-base font-semibold leading-tight text-slate-800 dark:text-slate-100">
                БренксЧат
              </p>
              <p className="text-xs font-medium text-tg-muted">
                {mode === 'reset' ? 'Восстановление' : 'Авторизация'}
              </p>
            </div>
          </div>

          <ThemeToggle />
        </div>

        <div className="mb-4">
          <h1 className="text-xl font-semibold tracking-normal text-slate-900 dark:text-white">
            {title}
          </h1>
          <p className="mt-1 text-sm text-tg-muted">{subtitle}</p>
        </div>

        {!pending && mode !== 'reset' ? (
          <div className="glass-segmented mb-4 flex p-1">
            <span
              className="pointer-events-none absolute bottom-1 left-1 top-1 rounded-[0.85rem] bg-white/85 shadow-md ring-1 ring-white/40 transition-transform duration-500 ease-[cubic-bezier(0.22,1,0.36,1)] will-change-transform dark:bg-zinc-700/75 dark:ring-white/10"
              style={{
                width: 'calc((100% - 8px - 4px) / 2)',
                transform:
                  mode === 'login'
                    ? 'translateX(0)'
                    : 'translateX(calc(100% + 4px))',
              }}
            />
            <button
              type="button"
              className={`relative z-10 flex-1 rounded-[0.85rem] py-2.5 text-sm font-semibold transition-colors duration-500 ${
                mode === 'login'
                  ? 'text-slate-900 dark:text-white'
                  : 'text-slate-600/90 hover:text-slate-800 dark:text-slate-300/80 dark:hover:text-slate-100'
              }`}
              onClick={() => switchMode('login')}
            >
              Вход
            </button>
            <button
              type="button"
              className={`relative z-10 flex-1 rounded-[0.85rem] py-2.5 text-sm font-semibold transition-colors duration-500 ${
                mode === 'register'
                  ? 'text-slate-900 dark:text-white'
                  : 'text-slate-600/90 hover:text-slate-800 dark:text-slate-300/80 dark:hover:text-slate-100'
              }`}
              onClick={() => switchMode('register')}
            >
              Регистрация
            </button>
          </div>
        ) : null}

        <form onSubmit={(e) => void submit(e)} className="space-y-3.5">
          {pending ? (
            <>
              <div>
                <label className="block text-xs font-medium text-slate-600 dark:text-slate-300">
                  Код из письма
                </label>
                <div className="shimmer-border mt-1.5">
                  <input
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    value={code}
                    onChange={(e) => setCode(e.target.value)}
                    className="login-input shimmer-border__inner"
                    placeholder="123456"
                  />
                </div>
              </div>
              {pending.kind === 'reset' ? (
                <div>
                  <label className="block text-xs font-medium text-slate-600 dark:text-slate-300">
                    Новый пароль
                  </label>
                  <div className="shimmer-border mt-1.5">
                    <input
                      type="password"
                      autoComplete="new-password"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    minLength={8}
                    maxLength={128}
                    className="login-input shimmer-border__inner"
                      placeholder="Новый пароль"
                    />
                  </div>
                </div>
              ) : null}
            </>
          ) : mode === 'reset' ? (
            <div>
              <label className="block text-xs font-medium text-slate-600 dark:text-slate-300">
                Логин или почта
              </label>
              <div className="shimmer-border mt-1.5">
                <input
                  autoComplete="username"
                  value={resetLogin}
                  onChange={(e) => setResetLogin(e.target.value)}
                  className="login-input shimmer-border__inner"
                  placeholder="login или mail@example.com"
                />
              </div>
            </div>
          ) : (
            <>
              <div>
                <label className="block text-xs font-medium text-slate-600 dark:text-slate-300">
                  Имя пользователя
                </label>
                <div className="shimmer-border mt-1.5">
                  <input
                    autoComplete="username"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    className="login-input shimmer-border__inner"
                    placeholder="Ваш логин"
                  />
                </div>
              </div>

              {mode === 'register' ? (
                <div>
                  <label className="block text-xs font-medium text-slate-600 dark:text-slate-300">
                    Почта
                  </label>
                  <div className="shimmer-border mt-1.5">
                    <input
                      type="email"
                      autoComplete="email"
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      className="login-input shimmer-border__inner"
                      placeholder="mail@example.com"
                    />
                  </div>
                </div>
              ) : null}

              <div>
                <label className="block text-xs font-medium text-slate-600 dark:text-slate-300">
                  Пароль
                </label>
                <div className="shimmer-border mt-1.5">
                  <input
                    type="password"
                    autoComplete={
                      mode === 'login' ? 'current-password' : 'new-password'
                    }
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    minLength={mode === 'register' ? 8 : undefined}
                    maxLength={128}
                    className="login-input shimmer-border__inner"
                    placeholder="Пароль"
                  />
                </div>
              </div>

              {mode === 'login' ? (
                <label className="flex cursor-pointer items-center justify-between gap-3 rounded-2xl border border-white/70 bg-white/55 px-3 py-2.5 text-sm shadow-sm backdrop-blur-xl transition hover:bg-white/75 dark:border-white/10 dark:bg-zinc-700/45 dark:hover:bg-zinc-700/65">
                  <span>
                    <span className="block font-semibold text-slate-700 dark:text-slate-100">
                      Запомнить меня
                    </span>
                    <span className="block text-xs text-tg-muted">
                      Не выходить на этом устройстве 30 дней
                    </span>
                  </span>
                  <input
                    type="checkbox"
                    checked={rememberMe}
                    onChange={(e) => setRememberMe(e.target.checked)}
                    className="peer sr-only"
                  />
                  <span className="relative h-6 w-11 shrink-0 rounded-full bg-slate-300 shadow-inner transition-colors duration-300 peer-checked:bg-slate-600 dark:bg-zinc-600 dark:peer-checked:bg-slate-300">
                    <span className="absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white shadow-md transition-transform duration-300 peer-checked:translate-x-5 dark:peer-checked:bg-zinc-800" />
                  </span>
                </label>
              ) : null}
            </>
          )}

          {notice ? (
            <p className="rounded-xl border border-emerald-200 bg-emerald-50/80 px-3 py-2 text-sm text-emerald-700 dark:border-emerald-400/20 dark:bg-emerald-400/10 dark:text-emerald-200">
              {notice}
            </p>
          ) : null}

          {error ? (
            <p className="animate-shake rounded-xl border border-red-200 bg-red-50/80 px-3 py-2 text-sm text-red-600 dark:border-red-500/20 dark:bg-red-500/10 dark:text-red-300">
              {error}
            </p>
          ) : null}

          <button type="submit" disabled={loading} className="login-submit">
            {loading ? (
              <span className="flex items-center justify-center gap-2">
                <svg
                  className="h-4 w-4 animate-spin"
                  viewBox="0 0 24 24"
                  fill="none"
                >
                  <circle
                    className="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    strokeWidth="4"
                  />
                  <path
                    className="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                  />
                </svg>
                Подождите...
              </span>
            ) : pending ? (
              'Подтвердить'
            ) : mode === 'login' ? (
              'Войти'
            ) : mode === 'register' ? (
              'Создать аккаунт'
            ) : (
              'Отправить код'
            )}
          </button>

          <div className="flex items-center justify-between text-xs font-medium text-tg-muted">
            {pending ? (
              <button type="button" onClick={() => setPending(null)}>
                Назад
              </button>
            ) : mode === 'reset' ? (
              <button type="button" onClick={() => switchMode('login')}>
                Вернуться ко входу
              </button>
            ) : (
              <button type="button" onClick={() => switchMode('reset')}>
                Забыли пароль?
              </button>
            )}
            {!pending && mode === 'login' ? (
              <span>Код придёт на почту</span>
            ) : null}
          </div>
        </form>

        <div className="download-shelf" aria-label="Скачать БренксЧат">
          <div className="download-shelf__header">
            <div>
              <p className="download-shelf__eyebrow">Приложение</p>
              <h2>БренксЧат на устройстве</h2>
            </div>
            <span>Desktop</span>
          </div>

          <div className="download-grid">
            {downloadPlatforms.map((platform) => {
              const content = (
                <>
                  <span className="download-platform__icon">
                    <PlatformIcon id={platform.id} />
                  </span>
                  <span className="download-platform__copy">
                    <strong>{platform.title}</strong>
                    <small>
                      {platform.href ? platform.subtitle : `(${platform.subtitle})`}
                    </small>
                  </span>
                </>
              );

              return platform.href ? (
                <a
                  key={platform.id}
                  className="download-platform download-platform--ready"
                  href={platform.href}
                  download
                >
                  {content}
                </a>
              ) : (
                <button
                  key={platform.id}
                  type="button"
                  className="download-platform download-platform--disabled"
                  disabled
                >
                  {content}
                </button>
              );
            })}
          </div>
        </div>
      </section>
    </main>
  );
}
