export function userSearchQuery(
  raw: string,
  options: { allowPlainUsername?: boolean } = {}
): string | null {
  const value = raw.trim();
  if (!value) return null;

  if (value.startsWith('@')) {
    const username = value.replace(/^@+/, '').trim();
    return username.length >= 2 ? `@${username}` : null;
  }

  if (value.toLowerCase().startsWith('id:')) {
    const id = value.slice(3).trim();
    return id.length >= 6 ? `id:${id}` : null;
  }

  const looksLikeUserId =
    /^user-[A-Za-z0-9_-]{2,}$/.test(value) ||
    /^[0-9a-f]{8}-[0-9a-f-]{13,}$/i.test(value) ||
    (/^[A-Za-z0-9_-]{12,96}$/.test(value) && /[-_0-9]/.test(value));

  if (looksLikeUserId) return value;
  if (options.allowPlainUsername && value.length >= 2) return value;
  return null;
}

export function isWaitingForSearchInput(
  raw: string,
  options: { allowPlainUsername?: boolean } = {}
): boolean {
  const value = raw.trim();
  if (!value) return true;
  return userSearchQuery(value, options) === null;
}
