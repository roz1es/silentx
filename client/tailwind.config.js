/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      colors: {
        tg: {
          bg: 'rgb(var(--tg-bg) / <alpha-value>)',
          panel: 'rgb(var(--tg-panel) / <alpha-value>)',
          bubble: 'rgb(var(--tg-bubble) / <alpha-value>)',
          mine: 'rgb(var(--tg-mine) / <alpha-value>)',
          accent: 'rgb(var(--tg-accent) / <alpha-value>)',
          muted: 'rgb(var(--tg-muted) / <alpha-value>)',
          border: 'rgb(var(--tg-border) / <alpha-value>)',
          hover: 'rgb(var(--tg-hover) / <alpha-value>)',
        },
      },
      keyframes: {
        'msg-in': {
          '0%': { opacity: '0', transform: 'translateY(8px) scale(0.98)' },
          '100%': { opacity: '1', transform: 'translateY(0) scale(1)' },
        },
      },
      animation: {
        'msg-in': 'msg-in 0.22s ease-out both',
      },
    },
  },
  plugins: [],
};
