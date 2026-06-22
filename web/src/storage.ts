const KEY = "rohomieo.session";

export interface SavedSession {
  signalingUrl: string;
  sessionId: string;
  pin: string;
}

export function loadSession(): Partial<SavedSession> {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return {};
    return JSON.parse(raw) as SavedSession;
  } catch {
    return {};
  }
}

export function saveSession(s: SavedSession) {
  localStorage.setItem(KEY, JSON.stringify(s));
}

export function clearSession() {
  localStorage.removeItem(KEY);
}
