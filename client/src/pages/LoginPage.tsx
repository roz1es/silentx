import { useState } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { ThemeToggle } from '@/components/ThemeToggle';

export function LoginPage() {
  const { user, loading, login, register } = useAuth();
  const [mode, setMode] = useState<'login' | 'register'>('login');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);

  if (user) return <Navigate to="/" replace />;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      if (mode === 'login') await login(username, password);
      else await register(username, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Ошибка');
    }
  };

  return (
    <div className="relative flex min-h-screen flex-col items-center justify-center bg-tg-bg px-4">
      <div className="absolute right-4 top-4">
        <ThemeToggle />
      </div>
      <div className="w-full max-w-sm rounded-3xl border border-tg-border bg-tg-panel p-8 shadow-xl">
        <div className="mb-6 text-center">
          <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-tg-accent to-sky-500 text-2xl font-bold text-white shadow-lg">
            S
          </div>
          <h1 className="mt-4 text-2xl font-bold text-slate-900 dark:text-white">
            Silentix
          </h1>
          <p className="mt-1 text-sm text-tg-muted">Мессенджер</p>
        </div>
        <div className="mb-4 flex rounded-xl bg-tg-hover p-1">
          <button
            type="button"
            className={`flex-1 rounded-lg py-2 text-sm font-medium ${
              mode === 'login' ? 'bg-tg-panel shadow' : 'text-tg-muted'
            }`}
            onClick={() => setMode('login')}
          >
            Вход
          </button>
          <button
            type="button"
            className={`flex-1 rounded-lg py-2 text-sm font-medium ${
              mode === 'register' ? 'bg-tg-panel shadow' : 'text-tg-muted'
            }`}
            onClick={() => setMode('register')}
          >
            Регистрация
          </button>
        </div>
        <form onSubmit={(e) => void submit(e)} className="space-y-4">
          <div>
            <label className="block text-xs font-medium text-tg-muted">
              Имя пользователя
            </label>
            <input
              autoComplete="username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="mt-1 w-full rounded-xl border border-tg-border bg-white px-3 py-2.5 text-slate-900 outline-none ring-tg-accent/30 focus:ring-2 dark:bg-slate-900/50 dark:text-slate-100"
              placeholder="alice"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-tg-muted">
              Пароль
            </label>
            <input
              type="password"
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 w-full rounded-xl border border-tg-border bg-white px-3 py-2.5 text-slate-900 outline-none ring-tg-accent/30 focus:ring-2 dark:bg-slate-900/50 dark:text-slate-100"
              placeholder="••••••"
            />
          </div>
          {error ? (
            <p className="text-sm text-red-500 dark:text-red-400">{error}</p>
          ) : null}
          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-xl bg-tg-accent py-3 text-sm font-semibold text-white shadow-lg transition hover:brightness-105 disabled:opacity-50"
          >
            {loading ? 'Подождите…' : mode === 'login' ? 'Войти' : 'Создать аккаунт'}
          </button>
        </form>
        <p className="mt-6 text-center text-xs text-tg-muted">
          Демо: пользователи <code className="rounded bg-tg-hover px-1">alice</code> /{' '}
          <code className="rounded bg-tg-hover px-1">alice</code>
        </p>
      </div>
    </div>
  );
}
