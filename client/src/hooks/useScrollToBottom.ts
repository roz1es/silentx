import { useEffect, useRef, type RefObject } from 'react';

export function useScrollToBottom<T extends HTMLElement>(
  deps: unknown[]
): RefObject<T> {
  const ref = useRef<T>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    
    // С flex-col-reverse scrollTop = 0 означает низ (новые сообщения)
    // Используем instant для мгновенной прокрутки
    el.scrollTop = 0;
  }, deps);

  return ref;
}
