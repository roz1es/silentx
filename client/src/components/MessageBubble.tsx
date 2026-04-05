import { useEffect, useMemo, useRef } from 'react';
import type { Message, User } from '@/types';
import { IconDrawingPin, IconPaperclip } from '@/components/icons';
import { UserAvatar } from '@/components/UserAvatar';
import { VoiceMessageBar, VideoNoteCircle } from '@/components/VoiceVideoMedia';
import { participantLabel } from '@/lib/userDisplay';
import { isEmojiOnlyMessage } from '@/lib/emojiOnly';

type SenderInfo = {
  username: string;
  displayName?: string;
  avatarUrl?: string;
};

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function HighlightedText({
  text,
  query,
}: {
  text: string;
  query: string;
}) {
  const q = query.trim();
  if (!q) return <>{text}</>;
  try {
    const parts = text.split(new RegExp(`(${escapeRe(q)})`, 'gi'));
    return (
      <>
        {parts.map((part, i) =>
          part.toLowerCase() === q.toLowerCase() ? (
            <mark
              key={i}
              className="rounded-sm bg-amber-200/90 px-0.5 dark:bg-amber-500/35"
            >
              {part}
            </mark>
          ) : (
            <span key={i}>{part}</span>
          )
        )}
      </>
    );
  } catch {
    return <>{text}</>;
  }
}

type Props = {
  message: Message;
  self: User;
  isGroup: boolean;
  sender?: SenderInfo | null;
  peerLabel?: string;
  selfInfo: SenderInfo;
  searchQuery?: string;
  onOpenPeerProfile?: () => void;
  onDelete?: () => void;
  onPin?: () => void;
  /** Это сообщение сейчас закреплено в чате */
  pinActive?: boolean;
  readReceipt?: 'sent' | 'read';
  isEditing?: boolean;
  editDraft?: string;
  onEditDraftChange?: (text: string) => void;
  onStartEdit?: () => void;
  onCommitEdit?: () => void;
  onCancelEdit?: () => void;
};

function formatTime(ts: number): string {
  return new Intl.DateTimeFormat('ru', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(ts));
}

function ReadTicks({ status }: { status: 'sent' | 'read' }) {
  const readColor = 'rgb(53, 175, 233)';
  const stroke = 1.85;
  return (
    <span
      className="inline-flex h-[14px] shrink-0 items-center text-slate-400 dark:text-slate-500"
      title={status === 'read' ? 'Прочитано' : 'Доставлено'}
      aria-label={status === 'read' ? 'Прочитано' : 'Доставлено'}
    >
      <svg
        width="20"
        height="12"
        viewBox="0 0 20 12"
        fill="none"
        aria-hidden
        className="block overflow-visible"
      >
        {status === 'read' ? (
          <g
            stroke={readColor}
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <polyline points="0.8,6.2 3.8,9.2 8.2,3.4" />
            <polyline points="5.8,6.2 8.8,9.2 18.5,1.2" />
          </g>
        ) : (
          <polyline
            points="2.2,6.2 6.2,10.2 17.8,1.5"
            stroke="currentColor"
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeLinejoin="round"
            fill="none"
            opacity={0.88}
          />
        )}
      </svg>
    </span>
  );
}

export function MessageBubble({
  message,
  self,
  isGroup,
  sender,
  peerLabel,
  selfInfo,
  searchQuery = '',
  onOpenPeerProfile,
  onDelete,
  onPin,
  pinActive = false,
  readReceipt,
  isEditing = false,
  editDraft = '',
  onEditDraftChange,
  onStartEdit,
  onCommitEdit,
  onCancelEdit,
}: Props) {
  const mine = message.senderId === self.id;
  const taRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (!isEditing) return;
    const el = taRef.current;
    if (!el) return;
    el.focus();
    el.setSelectionRange(el.value.length, el.value.length);
  }, [isEditing]);

  useEffect(() => {
    if (!isEditing) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onCancelEdit?.();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [isEditing, onCancelEdit]);

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
  const canEdit =
    mine &&
    !message.deleted &&
    !media &&
    !legacyImg &&
    onStartEdit &&
    onCommitEdit &&
    onCancelEdit &&
    onEditDraftChange;

  const textTrim = message.text.trim();
  const hasText = textTrim && textTrim !== '\u00a0';
  const emojiLarge =
    hasText && isEmojiOnlyMessage(message.text) && !isEditing;

  const isVoiceOrVideoNote =
    media?.kind === 'voice' || media?.kind === 'video_note';

  const bubble = (
    <div
      className={`relative max-w-[min(80vw,28rem)] rounded-2xl px-2.5 py-1.5 text-[13px] shadow-sm sm:px-3 sm:py-2 sm:text-[15px] ${
      isVoiceOrVideoNote
        ? 'bg-transparent shadow-none'
        : mine
          ? 'rounded-br-md bg-tg-mine text-slate-900 dark:text-slate-50'
          : 'rounded-bl-md bg-tg-bubble text-slate-900 dark:text-slate-100'
    }`}
    >
      <div className="absolute -right-1 -top-1 flex gap-0.5 opacity-0 transition group-hover/msg:opacity-100">
        {onPin ? (
          <button
            type="button"
            title={pinActive ? 'Снять закреп' : 'Закрепить'}
            onClick={onPin}
            className={`rounded-full p-1 shadow ${
              pinActive
                ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/50 dark:text-amber-200'
                : 'bg-white/95 text-slate-600 dark:bg-slate-800/95 dark:text-slate-200'
            }`}
          >
            <IconDrawingPin className="h-3 w-3" />
          </button>
        ) : null}
        {canEdit && !isEditing ? (
          <button
            type="button"
            title="Изменить"
            onClick={onStartEdit}
            className="rounded-full bg-white/95 px-2 py-0.5 text-[10px] font-semibold text-slate-600 shadow dark:bg-slate-800/95 dark:text-slate-200"
          >
            изм.
          </button>
        ) : null}
        {onDelete ? (
          <button
            type="button"
            title="Удалить"
            onClick={onDelete}
            className="rounded-full bg-white/95 px-2 py-0.5 text-[11px] font-semibold text-slate-600 shadow dark:bg-slate-800/95 dark:text-slate-200"
          >
            ×
          </button>
        ) : null}
      </div>
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
        <div className="mb-1">
          <VideoNoteCircle dataUrl={media.dataUrl} />
        </div>
      ) : null}

      {media?.kind === 'voice' ? (
        <div className="mb-1">
          <VoiceMessageBar
            dataUrl={media.dataUrl}
            durationMs={media.durationMs}
            mine={mine}
          />
        </div>
      ) : null}

      {media?.kind === 'file' ? (
        <a
          href={media.dataUrl}
          download={media.fileName ?? 'file'}
          className="mb-1 flex items-center gap-2 break-all rounded-lg bg-black/5 px-2 py-2 text-sm text-tg-accent underline dark:bg-white/10"
        >
          <IconPaperclip className="h-4 w-4 shrink-0 opacity-80" />
          {media.fileName ?? 'Файл'}
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

      {isEditing && canEdit ? (
        <div className="space-y-2">
          <textarea
            ref={taRef}
            value={editDraft}
            onChange={(e) => onEditDraftChange(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                onCommitEdit();
              }
            }}
            rows={3}
            maxLength={12000}
            className="w-full resize-y rounded-lg border border-tg-border bg-white/90 px-2 py-1.5 text-sm text-slate-900 outline-none focus:ring-2 focus:ring-tg-accent/30 dark:bg-slate-900/80 dark:text-slate-100 sm:text-[15px]"
          />
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={onCancelEdit}
              className="rounded-lg bg-black/5 px-3 py-1 text-xs font-medium dark:bg-white/10"
            >
              Отмена
            </button>
            <button
              type="button"
              onClick={onCommitEdit}
              disabled={!editDraft.trim()}
              className="rounded-lg bg-tg-accent px-3 py-1 text-xs font-semibold text-white disabled:opacity-40"
            >
              Сохранить
            </button>
          </div>
        </div>
      ) : hasText ? (
        <p
          className={`whitespace-pre-wrap break-words leading-snug ${
            emojiLarge
              ? 'text-center text-[2rem] leading-none tracking-wide sm:text-[2.35rem] [&_mark]:text-[2rem] sm:[&_mark]:text-[2.35rem]'
              : 'text-[14px] sm:text-[15px]'
          }`}
        >
          <HighlightedText text={message.text} query={searchQuery} />
        </p>
      ) : null}

      <div className="mt-0.5 flex flex-wrap items-center justify-end gap-x-1 text-[10px] text-tg-muted sm:mt-1 sm:text-[11px]">
        {message.editedAt ? (
          <span className="opacity-75">изменено</span>
        ) : null}
        <span>{formatTime(message.createdAt)}</span>
        {mine && readReceipt ? <ReadTicks status={readReceipt} /> : null}
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
