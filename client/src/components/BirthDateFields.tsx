import { useEffect, useMemo, useState } from 'react';

type Props = {
  value: string;
  onChange: (iso: string) => void;
  disabled?: boolean;
};

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

function daysInMonth(y: number, m: number): number {
  return new Date(y, m, 0).getDate();
}

export function BirthDateFields({ value, onChange, disabled }: Props) {
  const [y, setY] = useState('');
  const [m, setM] = useState('');
  const [d, setD] = useState('');

  useEffect(() => {
    if (value?.length >= 10) {
      setY(value.slice(0, 4));
      setM(value.slice(5, 7));
      setD(value.slice(8, 10));
    } else {
      setY('');
      setM('');
      setD('');
    }
  }, [value]);

  const years = useMemo(() => {
    const cy = new Date().getFullYear();
    const list: string[] = [];
    for (let yv = cy; yv >= 1920; yv--) list.push(String(yv));
    return list;
  }, []);

  const months = useMemo(
    () =>
      Array.from({ length: 12 }, (_, i) => ({
        v: pad2(i + 1),
        label: new Date(2000, i, 1).toLocaleString('ru', { month: 'long' }),
      })),
    []
  );

  const yi = y ? parseInt(y, 10) : 0;
  const mi = m ? parseInt(m, 10) : 0;
  const maxDay = yi && mi ? daysInMonth(yi, mi) : 31;

  const days = useMemo(() => {
    return Array.from({ length: maxDay }, (_, i) => pad2(i + 1));
  }, [maxDay]);

  const emit = (yy: string, mm: string, dd: string) => {
    setY(yy);
    setM(mm);
    setD(dd);
    if (yy && mm && dd) {
      let dn = parseInt(dd, 10);
      const yNum = parseInt(yy, 10);
      const mNum = parseInt(mm, 10);
      const cap = daysInMonth(yNum, mNum);
      if (dn > cap) dn = cap;
      onChange(`${yy}-${mm}-${pad2(dn)}`);
    } else {
      onChange('');
    }
  };

  const selectClass =
    'w-full appearance-none rounded-2xl border border-tg-border/80 bg-slate-100/90 py-3 pl-3 pr-8 text-center text-[15px] font-medium text-slate-900 shadow-sm outline-none transition focus:border-tg-accent focus:ring-2 focus:ring-[rgb(var(--tg-accent))]/25 disabled:opacity-50 dark:border-slate-600 dark:bg-slate-800/90 dark:text-slate-100';

  return (
    <div className="birth-date-fields space-y-2">
      <p className="text-[11px] font-medium uppercase tracking-wide text-tg-muted">
        Дата рождения
      </p>
      <div className="grid grid-cols-3 gap-2">
        <div className="relative">
          <select
            aria-label="День"
            disabled={disabled}
            value={d}
            onChange={(e) => emit(y, m, e.target.value)}
            className={selectClass}
          >
            <option value="">День</option>
            {days.map((day) => (
              <option key={day} value={day}>
                {parseInt(day, 10)}
              </option>
            ))}
          </select>
          <span className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-tg-muted">
            <Chevron />
          </span>
        </div>
        <div className="relative">
          <select
            aria-label="Месяц"
            disabled={disabled}
            value={m}
            onChange={(e) => emit(y, e.target.value, d)}
            className={selectClass}
          >
            <option value="">Месяц</option>
            {months.map((mo) => (
              <option key={mo.v} value={mo.v}>
                {mo.label}
              </option>
            ))}
          </select>
          <span className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-tg-muted">
            <Chevron />
          </span>
        </div>
        <div className="relative">
          <select
            aria-label="Год"
            disabled={disabled}
            value={y}
            onChange={(e) => emit(e.target.value, m, d)}
            className={selectClass}
          >
            <option value="">Год</option>
            {years.map((year) => (
              <option key={year} value={year}>
                {year}
              </option>
            ))}
          </select>
          <span className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 text-tg-muted">
            <Chevron />
          </span>
        </div>
      </div>
    </div>
  );
}

function Chevron() {
  return (
    <svg
      width="12"
      height="12"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      aria-hidden
    >
      <path d="M6 9l6 6 6-6" />
    </svg>
  );
}
