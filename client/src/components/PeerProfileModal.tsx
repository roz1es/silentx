import { useEffect, useMemo, useState } from 'react';
import * as api from '@/lib/api';
import type { Message, User } from '@/types';
import { useAuth } from '@/contexts/AuthContext';
import { useMessenger } from '@/contexts/MessengerContext';
import { useCall } from '@/contexts/CallContext';
import { participantLabel } from '@/lib/userDisplay';
import { UserAvatar } from '@/components/UserAvatar';
import { VideoNoteCard, VoiceMessageBar } from '@/components/VoiceVideoMedia';
import { IconClose, IconPhone, IconSend } from '@/components/icons';
import { PhotoViewer } from '@/components/PhotoViewer';

type Props = {
  userId: string | null;
  onClose: () => void;
};

export function PeerProfileModal({ userId, onClose }: Props) {
  const { user: viewer } = useAuth();
  const { activeChat, messages } = useMessenger();
  const { startCall } = useCall();
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<'photo' | 'voice' | 'video' | 'file'>('photo');
  const [openPhotoIndex, setOpenPhotoIndex] = useState<number | null>(null);
  const [shareCopied, setShareCopied] = useState(false);

  useEffect(() => {
    if (!userId) {
      setUser(null);
      setError(null);
      setOpenPhotoIndex(null);
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError(null);
    setUser(null);
    api
      .fetchUserProfile(userId)
      .then(({ user: u }) => {
        if (!cancelled) setUser(u);
      })
      .catch((e: Error) => {
        if (!cancelled) setError(e.message ?? 'Ошибка загрузки');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [userId]);

  const label = user ? participantLabel(user) : '…';
  const sharedMedia = useMemo(() => {
    const inDirect = activeChat?.type === 'direct';
    return messages
      .filter((m) => {
        if (m.deleted) return false;
        if (!inDirect && m.senderId !== userId) return false;
        return m.media || m.imageUrl;
      })
      .reverse();
  }, [activeChat?.type, messages, userId]);
  const photos = sharedMedia.filter(
    (m) => m.media?.kind === 'image' || m.imageUrl
  );
  const voices = sharedMedia.filter(
    (m) => m.media?.kind === 'voice'
  );
  const videoNotes = sharedMedia.filter(
    (m) => m.media?.kind === 'video_note'
  );
  const files = sharedMedia.filter((m) => m.media?.kind === 'file');
  const current =
    tab === 'photo'
      ? photos
      : tab === 'voice'
        ? voices
        : tab === 'video'
          ? videoNotes
          : files;
  const photoViewerItems = photos.map((message) => ({
    id: message.id,
    src:
      message.media?.kind === 'image'
        ? message.media.dataUrl
        : message.imageUrl!,
    label: label,
    createdAt: message.createdAt,
  }));

  if (!userId) return null;

  const shareProfile = async () => {
    if (!user) return;
    const url = `${window.location.origin}/u/${encodeURIComponent(user.username)}`;
    try {
      if (navigator.share) {
        await navigator.share({
          title: `Профиль ${participantLabel(user)} в БренксЧат`,
          text: `@${user.username}`,
          url,
        });
        return;
      }
      await navigator.clipboard.writeText(url);
      setShareCopied(true);
      window.setTimeout(() => setShareCopied(false), 1800);
    } catch {
      /* пользователь мог закрыть системное окно */
    }
  };

  return (
    <div
      className="brenks-modal-backdrop fixed inset-0 z-[10020] flex items-center justify-center p-3 sm:p-4"
      role="dialog"
      aria-modal="true"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="brenks-modal-panel flex max-h-[min(92dvh,780px)] w-full max-w-md flex-col overflow-hidden rounded-[1.7rem]">
        <div className="flex shrink-0 items-center justify-between border-b border-tg-border/55 px-5 py-4">
          <div>
            <h2 className="text-lg font-semibold text-slate-900 dark:text-slate-100">
              Профиль
            </h2>
            <p className="text-xs text-tg-muted">Информация и общие медиа</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="brenks-profile-button flex h-10 w-10 items-center justify-center rounded-full"
            title="Закрыть"
          >
            <IconClose className="h-4 w-4" />
          </button>
        </div>

        <div className="brenks-modal-scroll scrollbar-thin tg-soft-scrollbar min-h-0 flex-1 overflow-y-auto px-5 pb-5">
          {loading ? (
            <p className="py-12 text-center text-sm text-tg-muted">Загрузка…</p>
          ) : error ? (
            <p className="py-12 text-center text-sm text-red-500">{error}</p>
          ) : user ? (
          <div className="flex flex-col items-center gap-4 pb-1 pt-6 text-center">
            <UserAvatar
              username={label}
              avatarUrl={user.avatarUrl}
              size="lg"
              className="ring-4 ring-white/55 shadow-[0_14px_34px_rgba(15,23,42,0.16)] dark:ring-white/10"
            />
            <div>
              <p className="text-xl font-semibold text-slate-900 dark:text-slate-100">
                {label}
              </p>
              <p className="text-sm text-tg-muted">@{user.username}</p>
            </div>
            <div className="grid w-full grid-cols-3 gap-2">
              <button
                type="button"
                onClick={onClose}
                className="brenks-profile-button flex items-center justify-center gap-1.5 rounded-2xl px-3 py-2 text-xs font-semibold"
              >
                <IconSend className="h-3.5 w-3.5" />
                Написать
              </button>
              <button
                type="button"
                disabled={user.privacy?.allowCalls === false}
                onClick={() => void startCall(user.id, 'audio')}
                className="brenks-profile-button flex items-center justify-center gap-1.5 rounded-2xl px-3 py-2 text-xs font-semibold disabled:opacity-45"
              >
                <IconPhone className="h-3.5 w-3.5" />
                Звонок
              </button>
              <button
                type="button"
                onClick={() => void shareProfile()}
                className="brenks-profile-button rounded-2xl px-3 py-2 text-xs font-semibold"
              >
                {shareCopied ? 'Готово' : 'Поделиться'}
              </button>
            </div>
            {viewer?.isAdmin ? (
              <div className="brenks-profile-card w-full rounded-2xl px-4 py-3 text-left">
                <p className="text-[11px] uppercase tracking-wide text-tg-muted">
                  ID
                </p>
                <p className="break-all font-mono text-xs text-slate-800 dark:text-slate-200">
                  {user.id}
                </p>
              </div>
            ) : null}
            {user.phone?.trim() ? (
              <div className="brenks-profile-card w-full rounded-2xl px-4 py-3 text-left">
                <p className="text-[11px] uppercase tracking-wide text-tg-muted">
                  Телефон
                </p>
                <p className="text-sm text-slate-800 dark:text-slate-100">
                  {user.phone}
                </p>
              </div>
            ) : null}
            {user.birthDate ? (
              <div className="brenks-profile-card w-full rounded-2xl px-4 py-3 text-left">
                <p className="text-[11px] uppercase tracking-wide text-tg-muted">
                  Дата рождения
                </p>
                <p className="text-sm text-slate-800 dark:text-slate-100">
                  {new Intl.DateTimeFormat('ru', {
                    day: 'numeric',
                    month: 'long',
                    year: 'numeric',
                  }).format(new Date(user.birthDate + 'T12:00:00'))}
                </p>
              </div>
            ) : null}
            {user.bio?.trim() ? (
              <p className="brenks-profile-card w-full rounded-2xl px-4 py-3 text-left text-sm text-slate-700 dark:text-slate-200">
                {user.bio}
              </p>
            ) : (
              <p className="text-sm text-tg-muted">Нет описания</p>
            )}
            <div className="w-full pt-2 text-left">
              <div className="brenks-modal-field mb-3 grid grid-cols-4 gap-1 rounded-2xl p-1">
                <MediaTab
                  active={tab === 'photo'}
                  label={`Фото ${photos.length}`}
                  onClick={() => setTab('photo')}
                />
                <MediaTab
                  active={tab === 'voice'}
                  label={`ГС ${voices.length}`}
                  onClick={() => setTab('voice')}
                />
                <MediaTab
                  active={tab === 'video'}
                  label={`Кружки ${videoNotes.length}`}
                  onClick={() => setTab('video')}
                />
                <MediaTab
                  active={tab === 'file'}
                  label={`Файлы ${files.length}`}
                  onClick={() => setTab('file')}
                />
              </div>
              {current.length === 0 ? (
                <p className="brenks-profile-card rounded-2xl border-dashed px-3 py-5 text-center text-sm text-tg-muted">
                  Пока нет вложений
                </p>
              ) : tab === 'photo' ? (
                <div className="grid grid-cols-3 gap-1.5">
                  {photos.slice(0, 60).map((m, index) => {
                    const src =
                      m.media?.kind === 'image' ? m.media.dataUrl : m.imageUrl!;
                    return (
                      <button
                        key={m.id}
                        type="button"
                        onClick={() => setOpenPhotoIndex(index)}
                        className="aspect-square overflow-hidden rounded-xl border border-white/40 bg-tg-hover shadow-sm focus:outline-none focus:ring-2 focus:ring-tg-accent/45 dark:border-white/10"
                        title={formatMediaTime(m)}
                      >
                        <img
                          src={src}
                          alt=""
                          className="h-full w-full object-cover transition hover:scale-[1.04]"
                        />
                      </button>
                    );
                  })}
                </div>
              ) : (
                <div className="space-y-2">
                  {current.slice(0, 40).map((m) => (
                    <MediaRow key={m.id} message={m} />
                  ))}
                </div>
              )}
            </div>
          </div>
          ) : null}
        </div>
      </div>
      <PhotoViewer
        items={photoViewerItems}
        index={openPhotoIndex}
        onIndexChange={setOpenPhotoIndex}
      />
    </div>
  );
}

function MediaTab({
  active,
  label,
  onClick,
}: {
  active: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-xl px-2 py-2 text-xs font-semibold transition ${
        active
          ? 'bg-white/72 text-slate-900 shadow-sm dark:bg-white/10 dark:text-slate-100'
          : 'text-tg-muted hover:bg-white/45 dark:hover:bg-white/[0.06]'
      }`}
    >
      {label}
    </button>
  );
}

function formatMediaTime(message: Message) {
  return new Intl.DateTimeFormat('ru', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(message.createdAt));
}

function MediaRow({ message }: { message: Message }) {
  const media = message.media;
  if (!media) return null;
  const title =
    media.kind === 'voice'
      ? 'Голосовое сообщение'
      : media.kind === 'video_note'
        ? 'Видеокружок'
        : media.fileName ?? 'Файл';
  return (
    <div className="brenks-profile-card rounded-2xl p-3">
      <div className="mb-2 flex items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-slate-800 dark:text-slate-100">
            {title}
          </p>
          <p className="text-xs text-tg-muted">{formatMediaTime(message)}</p>
        </div>
        {media.kind === 'file' ? (
          <a
            href={media.dataUrl}
            download={media.fileName ?? 'file'}
            className="shrink-0 rounded-xl bg-tg-panel px-3 py-1.5 text-xs font-semibold text-tg-accent shadow-sm"
          >
            Скачать
          </a>
        ) : null}
      </div>
      {media.kind === 'voice' ? (
        <VoiceMessageBar
          dataUrl={media.dataUrl}
          durationMs={media.durationMs}
          mine={false}
        />
      ) : null}
      {media.kind === 'video_note' ? (
        <div className="flex justify-center">
          <VideoNoteCard dataUrl={media.dataUrl} />
        </div>
      ) : null}
    </div>
  );
}
