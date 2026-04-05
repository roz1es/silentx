/** Сообщение состоит только из эмодзи (и пробелов) — показываем крупнее */
export function isEmojiOnlyMessage(raw: string): boolean {
  const text = raw.replace(/\u00a0/g, ' ').trim();
  if (!text) return false;
  if (typeof Intl !== 'undefined' && 'Segmenter' in Intl) {
    const seg = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
    let has = false;
    for (const { segment } of seg.segment(text)) {
      const s = segment.replace(/\s/g, '');
      if (!s) continue;
      has = true;
      for (const ch of s) {
        const cp = ch.codePointAt(0) ?? 0;
        if (cp === 0xfe0f || cp === 0x200d) continue;
        if (cp >= 0x30 && cp <= 0x39) continue;
        if (cp === 0x23 || cp === 0x2a) continue;
        if (
          !/\p{Extended_Pictographic}/u.test(ch) &&
          !(cp >= 0x1f1e6 && cp <= 0x1f1ff)
        ) {
          return false;
        }
      }
    }
    return has;
  }
  return /^[\s\p{Extended_Pictographic}\uFE0F\u200D#*0-9]+$/u.test(text);
}
