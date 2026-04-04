type Props = {
  username: string;
  avatarUrl?: string;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
};

const sizeClass = {
  sm: 'h-9 w-9 text-sm',
  md: 'h-12 w-12 text-lg',
  lg: 'h-16 w-16 text-2xl',
};

export function UserAvatar({
  username,
  avatarUrl,
  size = 'md',
  className = '',
}: Props) {
  const letter = username.slice(0, 1).toUpperCase() || '?';
  if (avatarUrl) {
    return (
      <img
        src={avatarUrl}
        alt=""
        className={`${sizeClass[size]} shrink-0 rounded-full object-cover ${className}`}
      />
    );
  }
  return (
    <div
      className={`flex ${sizeClass[size]} shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-tg-accent/90 to-sky-500/80 font-semibold text-white shadow-inner ${className}`}
    >
      {letter}
    </div>
  );
}
