import { createContext, useContext, useState, useCallback, type ReactNode } from 'react';
import { api, getToken, setToken } from './api';

interface AuthState {
  authenticated: boolean;
  agentName: string;
  login: (username: string, password: string) => Promise<void>;
  pair: (pairingCode: string) => Promise<void>;
  register: (pairingCode: string, username: string, password: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [authenticated, setAuthenticated] = useState(() => !!getToken());
  const [agentName, setAgentName] = useState('');

  const settle = useCallback((res: { deviceToken: string; agentName: string }) => {
    setToken(res.deviceToken);
    setAgentName(res.agentName);
    setAuthenticated(true);
  }, []);

  const login = useCallback(
    async (username: string, password: string) => settle(await api.login(username, password)),
    [settle],
  );
  const pair = useCallback(
    async (pairingCode: string) => settle(await api.pair(pairingCode)),
    [settle],
  );
  const register = useCallback(
    async (pairingCode: string, username: string, password: string) =>
      settle(await api.register(pairingCode, username, password)),
    [settle],
  );
  const logout = useCallback(() => {
    setToken(null);
    setAuthenticated(false);
  }, []);

  return (
    <AuthContext.Provider value={{ authenticated, agentName, login, pair, register, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}
