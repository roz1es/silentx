import { IconMoon, IconSun } from '@/components/icons';
import { useTheme } from '@/contexts/ThemeContext';

export function ThemeToggle() {
  const { theme, toggleTheme } = useTheme();
  const dark = theme === 'dark';
  return (
    <button
      type="button"
      onClick={toggleTheme}
      className="group relative grid h-9 w-[3.85rem] shrink-0 grid-cols-2 items-center overflow-hidden rounded-full border border-white/70 bg-white/75 p-0.5 text-tg-muted shadow-sm ring-1 ring-black/5 backdrop-blur-xl transition-all duration-300 hover:bg-white dark:border-white/10 dark:bg-zinc-700/70 dark:ring-white/10 dark:hover:bg-zinc-700/90"
      title={dark ? 'Светлая тема' : 'Тёмная тема'}
      aria-label="Переключить тему"
    >
      <span
        className={`absolute left-0.5 top-0.5 h-8 w-8 rounded-full bg-slate-900/85 shadow-md transition-transform duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] dark:bg-white ${
          dark ? 'translate-x-[1.55rem]' : 'translate-x-0'
        }`}
        aria-hidden
      />
      <span
        className={`relative z-10 flex h-8 items-center justify-center rounded-full transition-colors ${
          dark ? 'text-slate-400' : 'text-white'
        }`}
      >
        <IconSun className="h-4 w-4" />
      </span>
      <span
        className={`relative z-10 flex h-8 items-center justify-center rounded-full transition-colors ${
          dark ? 'text-zinc-800' : 'text-slate-400'
        }`}
      >
        <IconMoon className="h-4 w-4" />
      </span>
    </button>
  );
}
