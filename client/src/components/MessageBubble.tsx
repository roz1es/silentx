import { useMemo } from 'react';
import type { Message, User } from '@/types';
import { UserAvatar } from '@/components/UserAvatar';
import { participantLabel } from '@/lib/userDisplay';

type SenderInfo = {
  username: string;
  displayName?: string;
  avatarUrl?: string;
};

type Props = {
  message: Message;
  self: User;
  isGroup: boolean;
  sender?: SenderInfo | null;
  peerLabel?: string;
  selfInfo: SenderInfo;
  onOpenPeerProfile?: () => void;
  onDelete?: () => void;
  readLabel?: string;
};

function formatTime(ts: number): string {
  return new Intl.DateTimeFormat('ru', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(ts));
}

export function MessageBubble({
  message,
  self,
  isGroup,
  sender,
  peerLabel,
  selfInfo,
  onOpenPeerProfile,
  onDelete,
  readLabel,
}: Props) {
  const mine = message.senderId === self.id;

  const showName = useMemo(
    () => !mine && peerLabel && isGroup,
    [mine, peerLabel, isGroup]
  );

  const showLeftAvatar = Boolean(!mine && sender);
  const showRightAvatar = mine && isGroup;

  const leftLabel = sender ? participantLabel(sender) : '?';
  const rightLabel = participantLabel(selfInfo);

  if (message.deleted) {
    return (
      <div
        className={`group/msg flex w-full animate-msg-in ${
          mine ? 'justify-end' : 'justify-start'
        }`}
      >
        <div
          className={`flex max-w-[min(92vw,30rem)] items-end gap-2 ${
            mine ? 'flex-row-reverse' : 'flex-row'
          }`}
        >
          {showLeftAvatar ? (
            <div className="w-9 shrink-0" aria-hidden />
          ) : null}
          <div
            className={`max-w-[min(72vw,28rem)] rounded-2xl px-3 py-2 text-sm italic text-tg-muted ${
              mine
                ? 'rounded-br-md bg-tg-mine/80'
                : 'rounded-bl-md bg-tg-bubble'
            }`}
          >
            Сообщение удалено
          </div>
          {showRightAvatar ? (
            <div className="w-9 shrink-0" aria-hidden />
          ) : null}
        </div>
      </div>
    );
  }

  const media = message.media;
  const legacyImg = message.imageUrl;

  const bubble = (
    <div
      className={`relative max-w-[min(85vw,28rem)] rounded-2xl px-3 py-2 shadow-sm ${
        mine
          ? 'rounded-br-md bg-tg-mine text-slate-900 dark:text-slate-50'
          : 'rounded-bl-md bg-tg-bubble text-slate-900 dark:text-slate-100'
      }`}
    >
      {onDelete ? (
        <button
          type="button"
          title="Удалить"
          onClick={onDelete}
          className="absolute -right-1 -top-1 rounded-full bg-white/90 px-1.5 py-0.5 text-[10px] text-slate-600 opacity-0 shadow transition group-hover/msg:opacity-100 dark:bg-slate-800/90 dark:text-slate-200"
        >
          ✕
        </button>
      ) : null}
      {showName ? (
        <button
          type="button"
          onClick={onOpenPeerProfile}
          className="mb-1 block w-full text-left text-xs font-semibold text-tg-accent hover:underline"
        >
          {peerLabel}
        </button>
      ) : null}

      {media?.kind === 'video_note' ? (
        <div className="mb-1 flex justify-center">
          <div className="h-48 w-48 overflow-hidden rounded-full bg-black/20 shadow-inner">
            <video
              src={media.dataUrl}
              controls
              className="h-full w-full object-cover"
              playsInline
            />
          </div>
        </div>
      ) : null}

      {media?.kind === 'voice' ? (
        <div className="mb-1 min-w-[200px]">
          <audio src={media.dataUrl} controls className="w-full" />
          {media.durationMs ? (
            <span className="text-[10px] text-tg-muted">
              {Math.round(media.durationMs / 1000)} сек
            </span>
          ) : null}
        </div>
      ) : null}

      {media?.kind === 'file' ? (
        <a
          href={media.dataUrl}
          download={media.fileName ?? 'file'}
          className="mb-1 flex items-center gap-2 break-all rounded-lg bg-black/5 px-2 py-2 text-sm text-tg-accent underline dark:bg-white/10"
        >
          📎 {media.fileName ?? 'Файл'}
        </a>
      ) : null}

      {media?.kind === 'image' || (legacyImg && !media) ? (
        <div className="mb-1 overflow-hidden rounded-lg">
          <img
            src={media?.kind === 'image' ? media.dataUrl : legacyImg!}
            alt=""
            className="max-h-64 w-full object-cover"
          />
        </div>
      ) : null}

      {message.text.trim() && message.text.trim() !== '\u00a0' ? (
        <p className="whitespace-pre-wrap break-words text-[15px] leading-snug">
          {message.text}
        </p>
      ) : null}

      <div className="mt-1 flex flex-wrap items-center justify-end gap-x-2 text-[11px] text-tg-muted">
        {mine && readLabel ? (
          <span className="text-tg-accent/90">{readLabel}</span>
        ) : null}
        <span>{formatTime(message.createdAt)}</span>
      </div>
    </div>
  );

  return (
    <div
      className={`group/msg flex w-full animate-msg-in ${
        mine ? 'justify-end' : 'justify-start'
      }`}
    >
      <div
        className={`flex max-w-[min(92vw,30rem)] items-end gap-2 ${
          mine ? 'flex-row-reverse' : 'flex-row'
        }`}
      >
        {showLeftAvatar && sender ? (
          <button
            type="button"
            title="Профиль"
            onClick={onOpenPeerProfile}
            className="shrink-0 rounded-full focus:outline-none focus:ring-2 focus:ring-tg-accent/50"
          >
            <UserAvatar
              username={leftLabel}
              avatarUrl={sender.avatarUrl}
              size="sm"
            />
          </button>
        ) : null}
        {bubble}
        {showRightAvatar ? (
          <div className="shrink-0">
            <UserAvatar
              username={rightLabel}
              avatarUrl={selfInfo.avatarUrl}
              size="sm"
            />
          </div>
        ) : null}
      </div>
    </div>
  );
}
