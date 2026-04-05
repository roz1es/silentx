import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import {
  type ChatWallpaperId,
  loadChatWallpaperId,
  saveChatWallpaperId,
} from '@/lib/chatWallpaper';

type Value = {
  wallpaperId: ChatWallpaperId;
  setWallpaperId: (id: ChatWallpaperId) => void;
};

const ChatWallpaperContext = createContext<Value | null>(null);

export function ChatWallpaperProvider({ children }: { children: ReactNode }) {
  const [wallpaperId, setWallpaperIdState] = useState<ChatWallpaperId>(
    loadChatWallpaperId
  );

  useEffect(() => {
    saveChatWallpaperId(wallpaperId);
  }, [wallpaperId]);

  const setWallpaperId = useCallback((id: ChatWallpaperId) => {
    setWallpaperIdState(id);
  }, []);

  const value = useMemo(
    () => ({ wallpaperId, setWallpaperId }),
    [wallpaperId, setWallpaperId]
  );

  return (
    <ChatWallpaperContext.Provider value={value}>
      {children}
    </ChatWallpaperContext.Provider>
  );
}

export function useChatWallpaper(): Value {
  const ctx = useContext(ChatWallpaperContext);
  if (!ctx) throw new Error('useChatWallpaper outside ChatWallpaperProvider');
  return ctx;
}
