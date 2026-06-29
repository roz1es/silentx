import { useEffect, type ReactNode } from 'react';
import {
  BrowserRouter,
  Link,
  Navigate,
  Route,
  Routes,
  useParams,
} from 'react-router-dom';
import { ThemeProvider } from '@/contexts/ThemeContext';
import { AuthProvider, useAuth } from '@/contexts/AuthContext';
import { AdminPage } from '@/pages/AdminPage';
import { LoginPage } from '@/pages/LoginPage';
import { MessengerPage } from '@/pages/MessengerPage';

function Protected({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  if (!user) return <Navigate to="/login" replace />;
  return <>{children}</>;
}

function AdminOnly({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  if (!user) return <Navigate to="/login" replace />;
  if (!user.isAdmin) return <Navigate to="/" replace />;
  return <>{children}</>;
}

function ProfileEntry() {
  const { user } = useAuth();
  const { username } = useParams<{ username?: string }>();
  const cleanUsername = username?.trim().replace(/^@+/, '') ?? '';
  const deepLink = `brenkschat://u/${encodeURIComponent(cleanUsername)}`;

  useEffect(() => {
    if (!cleanUsername) return undefined;
    const timer = window.setTimeout(() => {
      window.location.href = deepLink;
    }, 300);
    return () => window.clearTimeout(timer);
  }, [cleanUsername, deepLink]);

  if (user) return <MessengerPage />;

  return (
    <main className="profile-open-shell animated-bg bg-[rgb(var(--tg-bg))] text-slate-900 dark:text-slate-100">
      <section className="profile-open-card">
        <div className="profile-open-logo">Б</div>
        <p className="profile-open-kicker">Профиль БренксЧат</p>
        <h1>@{cleanUsername || 'username'}</h1>
        <p>
          Если приложение установлено, браузер предложит открыть этот профиль в
          БренксЧат. Если окно не появилось, нажмите кнопку ниже.
        </p>
        <button
          type="button"
          className="profile-open-primary"
          onClick={() => {
            window.location.href = deepLink;
          }}
          disabled={!cleanUsername}
        >
          Открыть в приложении
        </button>
        <Link className="profile-open-secondary" to="/login">
          Войти в веб-версию
        </Link>
      </section>
    </main>
  );
}

export default function App() {
  return (
    <ThemeProvider>
      <AuthProvider>
        <BrowserRouter>
          <Routes>
            <Route path="/login" element={<LoginPage />} />
            <Route
              path="/"
              element={
                <Protected>
                  <MessengerPage />
                </Protected>
              }
            />
            <Route
              path="/u/:username"
              element={<ProfileEntry />}
            />
            <Route
              path="/admin"
              element={
                <AdminOnly>
                  <AdminPage />
                </AdminOnly>
              }
            />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </BrowserRouter>
      </AuthProvider>
    </ThemeProvider>
  );
}
