export function ruSubscribers(n: number): string {
  const abs = n % 100;
  const l = n % 10;
  if (abs > 10 && abs < 20) return `${n} подписчиков`;
  if (l === 1) return `${n} подписчик`;
  if (l >= 2 && l <= 4) return `${n} подписчика`;
  return `${n} подписчиков`;
}

export function ruMembers(n: number): string {
  const abs = n % 100;
  const l = n % 10;
  if (abs > 10 && abs < 20) return `${n} участников`;
  if (l === 1) return `${n} участник`;
  if (l >= 2 && l <= 4) return `${n} участника`;
  return `${n} участников`;
}
