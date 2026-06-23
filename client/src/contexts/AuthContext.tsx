import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import type { User } from '@/types';
import * as api from '@/lib/api';
import type { ProfilePatch } from '@/lib/api';
import {
  resetE2eeKeyWithPassword,
  syncE2eeKeyWithPassword,
} from '@/lib/e2ee';
import {
  clearAuth,
  loadUser,
  saveAuth,
  updateStoredUser,
} from '@/lib/storage';

type AuthContextValue = {
  user: User | null;
  loading: boolean;
  login: (
    username: string,
    password: string,
    rememberMe: boolean
  ) => Promise<api.AuthSuccess | api.EmailCodeChallenge>;
  register: (
    username: string,
    email: string,
    password: string
  ) => Promise<api.AuthSuccess | api.EmailVerificationChallenge>;
  confirmLogin: (
    ticket: string,
    code: string,
    rememberMe: boolean,
    password: string
  ) => Promise<void>;
  confirmRegister: (
    ticket: string,
    code: string,
    password: string
  ) => Promise<void>;
  confirmEmailBind: (ticket: string, code: string) => Promise<void>;
  restoreE2eeKey: (password: string) => Promise<void>;
  resetE2eeKey: (password: string) => Promise<void>;
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
  updateProfile: (patch: ProfilePatch) => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(() => loadUser());
  const [loading, setLoading] = useState(false);

  const refreshUser = useCallback(async () => {
    const { user: u } = await api.fetchMe();
    updateStoredUser(u);
    setUser(u);
  }, []);

  const login = useCallback(async (
    username: string,
    password: string,
    rememberMe: boolean
  ) => {
    setLoading(true);
    try {
      const result = await api.login(username, password, rememberMe);
      if ('user' in result) {
        await syncE2eeKeyWithPassword(result.user.id, password).catch(
          (error) => console.warn('[e2ee] синхронизация ключа не удалась', error)
        );
        saveAuth(result.user);
        setUser(result.user);
      }
      return result;
    } finally {
      setLoading(false);
    }
  }, []);

  const register = useCallback(
    async (username: string, email: string, password: string) => {
      setLoading(true);
      try {
        const result = await api.register(username, email, password);
        if ('user' in result) {
          saveAuth(result.user);
          setUser(result.user);
        }
        return result;
      } finally {
        setLoading(false);
      }
    },
    []
  );

  const confirmLogin = useCallback(async (
    ticket: string,
    code: string,
    rememberMe: boolean,
    password: string
  ) => {
    setLoading(true);
    try {
      const { user: u } = await api.confirmLogin(ticket, code, rememberMe);
      await syncE2eeKeyWithPassword(u.id, password).catch(
        (error) => console.warn('[e2ee] синхронизация ключа не удалась', error)
      );
      saveAuth(u);
      setUser(u);
    } finally {
      setLoading(false);
    }
  }, []);

  const confirmRegister = useCallback(async (
    ticket: string,
    code: string,
    password: string
  ) => {
    setLoading(true);
    try {
      const { user: u } = await api.confirmRegister(ticket, code);
      await syncE2eeKeyWithPassword(u.id, password).catch(
        (error) => console.warn('[e2ee] создание копии ключа не удалось', error)
      );
      saveAuth(u);
      setUser(u);
    } finally {
      setLoading(false);
    }
  }, []);

  const confirmEmailBind = useCallback(async (ticket: string, code: string) => {
    setLoading(true);
    try {
      const { user: u } = await api.confirmEmailBind(ticket, code);
      updateStoredUser(u);
      setUser(u);
    } finally {
      setLoading(false);
    }
  }, []);

  const restoreE2eeKey = useCallback(
    async (password: string) => {
      if (!user) throw new Error('Требуется авторизация');
      await syncE2eeKeyWithPassword(user.id, password);
    },
    [user]
  );

  const resetE2eeKey = useCallback(
    async (password: string) => {
      if (!user) throw new Error('Требуется авторизация');
      await resetE2eeKeyWithPassword(user.id, password);
    },
    [user]
  );

  const logout = useCallback(async () => {
    try {
      await api.logout();
    } catch {
      // Локальный выход всё равно должен сработать при недоступном сервере.
    }
    clearAuth();
    setUser(null);
  }, []);

  const updateProfile = useCallback(async (patch: ProfilePatch) => {
    const { user: u } = await api.patchProfile(patch);
    updateStoredUser(u);
    setUser(u);
  }, []);

  useEffect(() => {
    refreshUser().catch(() => {
      clearAuth();
      setUser(null);
    });
  }, [refreshUser]);

  const value = useMemo(
    () => ({
      user,
      loading,
      login,
      register,
      confirmLogin,
      confirmRegister,
      confirmEmailBind,
      restoreE2eeKey,
      resetE2eeKey,
      logout,
      refreshUser,
      updateProfile,
    }),
    [
      user,
      loading,
      login,
      register,
      confirmLogin,
      confirmRegister,
      confirmEmailBind,
      restoreE2eeKey,
      resetE2eeKey,
      logout,
      refreshUser,
      updateProfile,
    ]
  );

  return (
    <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth outside AuthProvider');
  return ctx;
}
