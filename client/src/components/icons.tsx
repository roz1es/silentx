import type { ReactNode, SVGProps } from 'react';

type IconProps = SVGProps<SVGSVGElement> & { className?: string };

function strokeIcon(
  paths: ReactNode,
  props: IconProps,
  viewBox = '0 0 24 24'
) {
  const { className = 'h-5 w-5', ...rest } = props;
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox={viewBox}
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden
      {...rest}
    >
      {paths}
    </svg>
  );
}

export function IconPaperclip(props: IconProps) {
  return strokeIcon(
    <path d="m16.5 9.4-8.2 8.2a4 4 0 1 1-5.6-5.6l8.2-8.2a2.7 2.7 0 0 1 3.8 3.8l-8.3 8.3a1.3 1.3 0 0 1-1.9-1.9l7.4-7.4" />,
    props
  );
}

export function IconMic(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M12 14a3 3 0 0 0 3-3V6a3 3 0 0 0-6 0v5a3 3 0 0 0 3 3Z" />
      <path d="M19 11a7 7 0 0 1-14 0M12 18v3M8 21h8" />
    </>,
    props
  );
}

/** Video note / circle record */
export function IconVideoCircle(props: IconProps) {
  return strokeIcon(
    <>
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="3" />
    </>,
    props
  );
}

/** Прямая стрелка вправо — отправка */
export function IconSend(props: IconProps) {
  const { className = 'h-5 w-5', ...rest } = props;
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden
      {...rest}
    >
      <path d="M5 12h12" />
      <path d="m13 7 6 5-6 5" />
    </svg>
  );
}

export function IconSun(props: IconProps) {
  return strokeIcon(
    <>
      <circle cx="12" cy="12" r="3.5" />
      <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </>,
    props
  );
}

export function IconMoon(props: IconProps) {
  return strokeIcon(
    <path d="M21 14.5A8.5 8.5 0 0 1 9.5 3a6.5 6.5 0 1 0 11.5 11.5Z" />,
    props
  );
}

export function IconPhone(props: IconProps) {
  return strokeIcon(
    <path d="M5 4h3l2 5-2 1a12 12 0 0 0 6 6l1-2 5 2v3a1 1 0 0 1-1 1A17 17 0 0 1 5 5a1 1 0 0 1 1-1Z" />,
    props
  );
}

export function IconVideoCam(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M4 8a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8Z" />
      <path d="m15 10 5-3v10l-5-3" />
    </>,
    props
  );
}

export function IconSearch(props: IconProps) {
  return strokeIcon(
    <>
      <circle cx="11" cy="11" r="6.5" />
      <path d="M20 20 16 16" />
    </>,
    props
  );
}

export function IconPin(props: IconProps) {
  return strokeIcon(
    <path d="M12 17v5M8 9l-3-3 7-4 7 4-3 3v5l-4-3-4 3V9Z" />,
    props
  );
}

/** Канцелярская кнопка — для закрепления чатов и сообщений */
export function IconDrawingPin(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M12 2v2.5" />
      <path d="M9.5 4.5h5a1.5 1.5 0 0 1 1.5 1.5v2.2L18 11v1.5H6V11l2-2.8V6a1.5 1.5 0 0 1 1.5-1.5Z" />
      <path d="M12 12.5V22" />
      <path d="M9.5 20h5" />
    </>,
    props
  );
}

export function IconMoreVertical(props: IconProps) {
  return strokeIcon(
    <>
      <circle cx="12" cy="5" r="1.25" fill="currentColor" stroke="none" />
      <circle cx="12" cy="12" r="1.25" fill="currentColor" stroke="none" />
      <circle cx="12" cy="19" r="1.25" fill="currentColor" stroke="none" />
    </>,
    props
  );
}

export function IconArrowLeft(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M19 12H5" />
      <path d="M12 19 5 12l7-7" />
    </>,
    props
  );
}

export function IconChevronRight(props: IconProps) {
  return strokeIcon(<path d="m10 6 6 6-6 6" />, props);
}

export function IconMute(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M11 5 6 9H3v6h3l5 4V5Z" />
      <path d="m22 9-6 6M16 9l6 6" />
    </>,
    props
  );
}

export function IconMegaphone(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M6 9H4a1 1 0 0 0-1 1v4a1 1 0 0 0 1 1h2l6 3V6L6 9Z" />
      <path d="M18 9a4 4 0 0 1 0 6" />
    </>,
    props
  );
}

export function IconCheck(props: IconProps) {
  return strokeIcon(<path d="M5 12.5 9.5 17 19 7" />, props);
}

export function IconSmile(props: IconProps) {
  return strokeIcon(
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M8 14s1.5 2 4 2 4-2 4-2M9 9h.01M15 9h.01" />
    </>,
    props
  );
}

export function IconImage(props: IconProps) {
  return strokeIcon(
    <>
      <rect x="4" y="5" width="16" height="14" rx="2" />
      <circle cx="9" cy="10" r="1.5" fill="currentColor" stroke="none" />
      <path d="m4 17 5-5 4 4 3-3 4 4" />
    </>,
    props
  );
}

export function IconClose(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M6 6l12 12M18 6 6 18" />
    </>,
    props
  );
}

export function IconPalette(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M12 3a7 7 0 1 0 7 10.2c0 1-.8 1.8-1.8 1.8H12" />
      <circle cx="6.5" cy="11.5" r="1" fill="currentColor" stroke="none" />
      <circle cx="9.5" cy="7.5" r="1" fill="currentColor" stroke="none" />
      <circle cx="14.5" cy="6.5" r="1" fill="currentColor" stroke="none" />
      <circle cx="17.5" cy="11.5" r="1" fill="currentColor" stroke="none" />
    </>,
    props
  );
}

export function IconBell(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" />
      <path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
    </>,
    props
  );
}

export function IconBellOff(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9" />
      <path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
      <path d="M2 2l20 20" />
    </>,
    props
  );
}

export function IconX(props: IconProps) {
  return strokeIcon(
    <>
      <path d="M6 6l12 12M18 6 6 18" />
    </>,
    props
  );
}
