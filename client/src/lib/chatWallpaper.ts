const KEY = 'silentx_chat_wallpaper';

export type ChatWallpaperId =
  | 'classic'
  | 'plain'
  | 'bubbles'
  | 'ocean'
  | 'dusk'
  | 'mint';

export const CHAT_WALLPAPER_PRESETS: {
  id: ChatWallpaperId;
  label: string;
  previewClass: string;
}[] = [
  {
    id: 'classic',
    label: 'Классика',
    previewClass: 'bg-sky-100 dark:bg-slate-800',
  },
  {
    id: 'plain',
    label: 'Без узора',
    previewClass: 'bg-[#dfe8ee] dark:bg-[#1a222c]',
  },
  {
    id: 'bubbles',
    label: 'Пузыри',
    previewClass: 'bg-cyan-50 dark:bg-slate-900',
  },
  {
    id: 'ocean',
    label: 'Океан',
    previewClass: 'bg-gradient-to-b from-sky-200 to-cyan-100 dark:from-slate-900 dark:to-cyan-950',
  },
  {
    id: 'dusk',
    label: 'Сумерки',
    previewClass: 'bg-gradient-to-b from-violet-200/80 to-indigo-100 dark:from-indigo-950 dark:to-slate-950',
  },
  {
    id: 'mint',
    label: 'Мята',
    previewClass: 'bg-gradient-to-b from-emerald-100 to-teal-50 dark:from-emerald-950 dark:to-slate-900',
  },
];

export function loadChatWallpaperId(): ChatWallpaperId {
  try {
    const v = localStorage.getItem(KEY);
    if (
      v &&
      CHAT_WALLPAPER_PRESETS.some((p) => p.id === v)
    ) {
      return v as ChatWallpaperId;
    }
  } catch {
    /* noop */
  }
  return 'classic';
}

export function saveChatWallpaperId(id: ChatWallpaperId): void {
  try {
    localStorage.setItem(KEY, id);
  } catch {
    /* noop */
  }
}

/** CSS class for scrollable chat area (append to base layout classes) */
export function chatWallpaperClass(id: ChatWallpaperId): string {
  switch (id) {
    case 'plain':
      return 'chat-wallpaper-plain';
    case 'bubbles':
      return 'chat-wallpaper-bubbles';
    case 'ocean':
      return 'chat-wallpaper-ocean';
    case 'dusk':
      return 'chat-wallpaper-dusk';
    case 'mint':
      return 'chat-wallpaper-mint';
    default:
      return 'chat-wallpaper-classic';
  }
}
