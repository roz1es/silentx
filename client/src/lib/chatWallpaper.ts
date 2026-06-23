const KEY = 'brenkschat_chat_wallpaper';
const LEGACY_KEY = 'silentx_chat_wallpaper';

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
    previewClass: 'chat-wallpaper-classic',
  },
  {
    id: 'plain',
    label: 'Без узора',
    previewClass: 'chat-wallpaper-plain',
  },
  {
    id: 'bubbles',
    label: 'Пузыри',
    previewClass: 'chat-wallpaper-bubbles',
  },
  {
    id: 'ocean',
    label: 'Океан',
    previewClass: 'chat-wallpaper-ocean',
  },
  {
    id: 'dusk',
    label: 'Сумерки',
    previewClass: 'chat-wallpaper-dusk',
  },
  {
    id: 'mint',
    label: 'Мята',
    previewClass: 'chat-wallpaper-mint',
  },
];

function isChatWallpaperId(v: string | null): v is ChatWallpaperId {
  return Boolean(v && CHAT_WALLPAPER_PRESETS.some((p) => p.id === v));
}

export function loadChatWallpaperId(): ChatWallpaperId {
  try {
    const current = localStorage.getItem(KEY);
    if (isChatWallpaperId(current)) {
      return current;
    }

    const legacy = localStorage.getItem(LEGACY_KEY);
    if (isChatWallpaperId(legacy)) {
      localStorage.setItem(KEY, legacy);
      return legacy;
    }
  } catch {
    /* noop */
  }
  return 'classic';
}

export function saveChatWallpaperId(id: ChatWallpaperId): void {
  try {
    localStorage.setItem(KEY, id);
    localStorage.removeItem(LEGACY_KEY);
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
