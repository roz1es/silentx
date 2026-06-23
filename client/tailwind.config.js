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
        'float': {
          '0%, 100%': { transform: 'translateY(0) translateX(0)' },
          '25%': { transform: 'translateY(-10px) translateX(5px)' },
          '50%': { transform: 'translateY(-5px) translateX(-5px)' },
          '75%': { transform: 'translateY(-15px) translateX(3px)' },
        },
        'float-slow': {
          '0%, 100%': { transform: 'translateY(0) rotate(0deg)' },
          '33%': { transform: 'translateY(-8px) rotate(2deg)' },
          '66%': { transform: 'translateY(-4px) rotate(-1deg)' },
        },
        'pulse-glow': {
          '0%, 100%': { opacity: '0.3' },
          '50%': { opacity: '0.6' },
        },
        'gradient-shift': {
          '0%': { backgroundPosition: '0% 50%' },
          '50%': { backgroundPosition: '100% 50%' },
          '100%': { backgroundPosition: '0% 50%' },
        },
        'shake': {
          '0%, 100%': { transform: 'translateX(0)' },
          '10%, 30%, 50%, 70%, 90%': { transform: 'translateX(-2px)' },
          '20%, 40%, 60%, 80%': { transform: 'translateX(2px)' },
        },
        'pulse-ring': {
          '0%': { transform: 'scale(0.8)', opacity: '1' },
          '100%': { transform: 'scale(1.4)', opacity: '0' },
        },
      },
      animation: {
        'msg-in': 'msg-in 0.22s ease-out both',
        'float': 'float 15s ease-in-out infinite',
        'float-slow': 'float-slow 20s linear infinite',
        'pulse-glow': 'pulse-glow 8s ease-in-out infinite',
        'gradient-shift': 'gradient-shift 4s ease infinite',
        'shake': 'shake 0.5s ease-in-out',
        'pulse-ring': 'pulse-ring 1.5s ease-out infinite',
      },
    },
  },
  plugins: [],
};
