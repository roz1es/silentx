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
    <div className="relative flex min-h-screen flex-col items-center justify-center bg-gradient-to-br from-slate-100 via-slate-50 to-blue-100 px-4 dark:from-slate-900 dark:via-slate-950 dark:to-slate-900">
      <div className="absolute right-4 top-4">
        <ThemeToggle />
      </div>
      
      {/* Логотип */}
      <div className="mb-8 flex items-center justify-center">
        <div className="relative">
          <div className="flex h-20 w-20 items-center justify-center rounded-3xl bg-gradient-to-br from-sky-400 via-blue-500 to-indigo-600 shadow-xl shadow-blue-500/25 ring-1 ring-white/20 dark:shadow-blue-500/15">
            <span className="text-4xl font-bold text-white">S</span>
          </div>
          <div className="absolute -bottom-1 -right-1 flex h-7 w-7 items-center justify-center rounded-full bg-gradient-to-br from-emerald-400 to-emerald-500 text-xs font-bold text-white shadow-lg ring-2 ring-white dark:ring-slate-900">
            X
          </div>
        </div>
      </div>

      <div className="w-full max-w-sm rounded-3xl border border-white/30 bg-white/80 backdrop-blur-xl p-6 shadow-2xl dark:border-slate-700/50 dark:bg-slate-900/80">
        <div className="mb-5 text-center">
          <h1 className="text-2xl font-bold text-slate-900 dark:text-white">
            Добро пожаловать
          </h1>
          <p className="mt-1 text-sm text-slate-500 dark:text-slate-400">
            Войдите или создайте аккаунт
          </p>
        </div>
        
        {/* Переключатель */}
        <div className="mb-5 flex rounded-2xl bg-slate-100 p-1 dark:bg-slate-800/60">
          <button
            type="button"
            className={`flex-1 rounded-xl py-2.5 text-sm font-medium transition-all ${
              mode === 'login'
                ? 'bg-white text-slate-900 shadow-md dark:bg-slate-700 dark:text-white'
                : 'text-slate-500 dark:text-slate-400'
            }`}
            onClick={() => setMode('login')}
          >
            Вход
          </button>
          <button
            type="button"
            className={`flex-1 rounded-xl py-2.5 text-sm font-medium transition-all ${
              mode === 'register'
                ? 'bg-white text-slate-900 shadow-md dark:bg-slate-700 dark:text-white'
                : 'text-slate-500 dark:text-slate-400'
            }`}
            onClick={() => setMode('register')}
          >
            Регистрация
          </button>
        </div>
        
        <form onSubmit={(e) => void submit(e)} className="space-y-4">
          <div>
            <label className="block text-xs font-medium text-slate-600 dark:text-slate-400">
              Имя пользователя
            </label>
            <input
              autoComplete="username"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              className="mt-1.5 w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none ring-2 ring-blue-500/20 transition focus:ring-blue-500/40 dark:border-slate-700 dark:bg-slate-800 dark:text-white dark:ring-blue-500/10"
              placeholder="Придумайте логин"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-slate-600 dark:text-slate-400">
              Пароль
            </label>
            <input
              type="password"
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1.5 w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none ring-2 ring-blue-500/20 transition focus:ring-blue-500/40 dark:border-slate-700 dark:bg-slate-800 dark:text-white dark:ring-blue-500/10"
              placeholder="••••••••"
            />
          </div>
          {error ? (
            <p className="text-sm text-red-500 dark:text-red-400">{error}</p>
          ) : null}
          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-xl bg-gradient-to-r from-sky-400 to-blue-500 py-3.5 text-sm font-semibold text-white shadow-lg shadow-blue-500/25 transition-all hover:shadow-xl hover:shadow-blue-500/35 hover:brightness-105 active:scale-[0.98] disabled:opacity-50 dark:from-sky-500 dark:to-blue-600"
          >
            {loading ? 'Подождите…' : mode === 'login' ? 'Войти' : 'Создать аккаунт'}
          </button>
        </form>
      </div>
      
      <p className="mt-6 text-center text-xs text-slate-400 dark:text-slate-500">
        SilentX Messenger
      </p>
    </div>
  );
}
