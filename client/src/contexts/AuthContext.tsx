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
  clearAuth,
  loadToken,
  loadUser,
  saveAuth,
  updateStoredUser,
} from '@/lib/storage';

type AuthContextValue = {
  user: User | null;
  loading: boolean;
  login: (username: string, password: string) => Promise<void>;
  register: (username: string, password: string) => Promise<void>;
  logout: () => void;
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

  const login = useCallback(async (username: string, password: string) => {
    setLoading(true);
    try {
      const { user: u, token } = await api.login(username, password);
      saveAuth(u, token);
      setUser(u);
    } finally {
      setLoading(false);
    }
  }, []);

  const register = useCallback(async (username: string, password: string) => {
    setLoading(true);
    try {
      const { user: u, token } = await api.register(username, password);
      saveAuth(u, token);
      setUser(u);
    } finally {
      setLoading(false);
    }
  }, []);

  const logout = useCallback(() => {
    clearAuth();
    setUser(null);
  }, []);

  const updateProfile = useCallback(async (patch: ProfilePatch) => {
    const { user: u } = await api.patchProfile(patch);
    updateStoredUser(u);
    setUser(u);
  }, []);

  useEffect(() => {
    if (!loadToken()) return;
    refreshUser().catch(() => {});
  }, [refreshUser]);

  const value = useMemo(
    () => ({
      user,
      loading,
      login,
      register,
      logout,
      refreshUser,
      updateProfile,
    }),
    [user, loading, login, register, logout, refreshUser, updateProfile]
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
