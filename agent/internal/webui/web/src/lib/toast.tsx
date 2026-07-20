import { createContext, useContext, useRef, useState, type ReactNode } from 'react';
import { Check } from 'lucide-react';

interface ToastState {
  toast: (msg: string) => void;
}
const ToastContext = createContext<ToastState | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [msg, setMsg] = useState('');
  const [show, setShow] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  const toast = (m: string) => {
    setMsg(m);
    setShow(true);
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setShow(false), 2200);
  };

  return (
    <ToastContext.Provider value={{ toast }}>
      {children}
      <div className={`toast${show ? ' show' : ''}`}>
        <Check />
        <span>{msg}</span>
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastState {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error('useToast must be used inside ToastProvider');
  return ctx;
}
