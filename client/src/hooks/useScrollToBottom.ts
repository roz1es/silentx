import { useCallback, useEffect, useRef, type RefObject } from 'react';

export function useScrollToBottom<T extends HTMLElement>(
  deps: unknown[]
): RefObject<T> {
  const ref = useRef<T>(null);

  const scroll = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
  }, []);

  useEffect(() => {
    scroll();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- intentional
  }, deps);

  return ref;
}
