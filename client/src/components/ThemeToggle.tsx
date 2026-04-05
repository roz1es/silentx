import { IconMoon, IconSun } from '@/components/icons';
import { useTheme } from '@/contexts/ThemeContext';

export function ThemeToggle() {
  const { theme, toggleTheme } = useTheme();
  return (
    <button
      type="button"
      onClick={toggleTheme}
      className="flex h-9 w-9 items-center justify-center rounded-full text-tg-muted transition-all duration-500 ease-out hover:bg-tg-hover hover:text-slate-800 dark:hover:text-slate-100"
      title={theme === 'dark' ? 'Светлая тема' : 'Тёмная тема'}
      aria-label="Переключить тему"
    >
      {theme === 'dark' ? (
        <IconSun className="h-[1.15rem] w-[1.15rem]" />
      ) : (
        <IconMoon className="h-[1.15rem] w-[1.15rem]" />
      )}
    </button>
  );
}
