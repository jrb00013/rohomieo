import { useCallback, useEffect, useRef, useState } from "react";
import { ConnectionState, normalizedPointer, RohomieoViewer } from "./webrtc";
import { loadSession, saveSession } from "./storage";
import "./App.css";

const DEFAULT_WS =
  typeof location !== "undefined" && location.port === "5173"
    ? `${location.protocol === "https:" ? "wss" : "ws"}://${location.hostname}:8443/ws`
    : `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws`;

type Invite = {
  sessionId?: string;
  pin?: string;
  auto: boolean;
  signalingUrl?: string;
};

/** Survives React StrictMode remount (which would otherwise clear ?s=&p= then re-read empty). */
let cachedInvite: Invite | null = null;

function readInviteFromUrl(): Invite {
  if (cachedInvite) return cachedInvite;
  if (typeof location === "undefined") {
    cachedInvite = { auto: false };
    return cachedInvite;
  }

  // Prefer query string; also accept hash (? after #) for picky scanners / redirects.
  const raw =
    location.search.replace(/^\?/, "") ||
    (location.hash.includes("?")
      ? location.hash.slice(location.hash.indexOf("?") + 1)
      : location.hash.replace(/^#/, ""));
  const q = new URLSearchParams(raw);
  const sessionId = (q.get("s") ?? q.get("session") ?? undefined) || undefined;
  const pin = (q.get("p") ?? q.get("pin") ?? undefined) || undefined;
  const auto =
    q.get("auto") === "1" ||
    q.get("connect") === "1" ||
    (!!sessionId && !!pin && q.get("auto") !== "0");
  const ws = q.get("ws") ?? q.get("signaling") ?? undefined;

  cachedInvite = {
    sessionId: sessionId?.trim() || undefined,
    pin: pin?.trim() || undefined,
    auto,
    signalingUrl: ws ?? undefined,
  };

  // Strip invite from the address bar only after we've cached it.
  if (cachedInvite.sessionId || cachedInvite.pin) {
    try {
      const url = new URL(location.href);
      url.search = "";
      url.hash = "";
      history.replaceState({}, "", url.pathname);
    } catch {
      /* ignore */
    }
  }

  return cachedInvite;
}


export default function App() {
  const invite = readInviteFromUrl();
  const saved = loadSession();
  // QR / deep-link joins must use THIS page's host for signaling — never a
  // remembered wss://127.0.0.1 from a previous laptop browser session.
  const initialWs =
    invite.signalingUrl ??
    (invite.sessionId || invite.auto
      ? DEFAULT_WS
      : saved.signalingUrl ?? DEFAULT_WS);
  const [signalingUrl, setSignalingUrl] = useState(() => {
    // Phone opened LAN URL but still had localhost saved — force page host.
    if (
      typeof location !== "undefined" &&
      !/^(127\.0\.0\.1|localhost)$/i.test(location.hostname) &&
      /wss?:\/\/(127\.0\.0\.1|localhost)\b/i.test(initialWs)
    ) {
      return DEFAULT_WS;
    }
    return initialWs;
  });
  const [sessionId, setSessionId] = useState(
    invite.sessionId ?? saved.sessionId ?? ""
  );
  const [pin, setPin] = useState(invite.pin ?? saved.pin ?? "");
  const [state, setState] = useState<ConnectionState>("disconnected");
  const [detail, setDetail] = useState(
    invite.auto && invite.sessionId && invite.pin ? "Joining from QR…" : ""
  );
  const [keyboardOpen, setKeyboardOpen] = useState(false);
  const [typed, setTyped] = useState("");
  const [remember, setRemember] = useState(true);
  const [fullscreen, setFullscreen] = useState(false);
  const autoStarted = useRef(false);

  const videoRef = useRef<HTMLVideoElement>(null);
  const frameRef = useRef<HTMLImageElement>(null);
  const surfaceRef = useRef<HTMLDivElement>(null);
  const viewerRef = useRef<RohomieoViewer | null>(null);
  const mediaAspectRef = useRef<number>(16 / 10);

  useEffect(() => {
    const v = viewerRef.current;
    return () => v?.disconnect();
  }, []);

  useEffect(() => {
    const onFs = () => setFullscreen(!!document.fullscreenElement);
    document.addEventListener("fullscreenchange", onFs);
    return () => document.removeEventListener("fullscreenchange", onFs);
  }, []);

  const connect = useCallback(() => {
    if (!sessionId.trim() || !pin.trim()) {
      setDetail("Enter session ID and PIN from the host");
      return;
    }
    if (remember) {
      saveSession({
        signalingUrl: signalingUrl.trim(),
        sessionId: sessionId.trim(),
        pin: pin.trim(),
      });
    }
    const viewer = new RohomieoViewer({
      onState: (s, d) => {
        setState(s);
        setDetail(d ?? "");
      },
      onVideo: (stream) => {
        const el = videoRef.current;
        if (!el) return;
        el.srcObject = stream;
        el.muted = true;
        el.playsInline = true;
        void el.play().catch(() => {
          setDetail("Tap the screen if video does not start");
        });
      },
      onFrame: (url) => {
        const img = frameRef.current;
        if (img) {
          img.onload = () => {
            if (img.naturalWidth > 0 && img.naturalHeight > 0) {
              mediaAspectRef.current = img.naturalWidth / img.naturalHeight;
            }
          };
          img.src = url;
          img.style.display = "block";
        }
        // Phones often get a black H.264 video element; JPEG is the real picture.
        if (videoRef.current) videoRef.current.style.display = "none";
      },
    });
    viewerRef.current = viewer;
    viewer.connect(signalingUrl, sessionId.trim(), pin.trim());
  }, [signalingUrl, sessionId, pin, remember]);

  // Mark started only when connect() actually runs. React StrictMode remounts
  // clear the timeout; if we flipped the flag on schedule, remount would skip
  // forever and leave "Joining from QR…" stuck on disconnected.
  useEffect(() => {
    if (!invite.auto) return;
    if (!sessionId.trim() || !pin.trim()) return;
    const t = window.setTimeout(() => {
      if (autoStarted.current) return;
      autoStarted.current = true;
      connect();
    }, 50);
    return () => clearTimeout(t);
  }, [invite.auto, sessionId, pin, connect]);

  const disconnect = () => viewerRef.current?.disconnect();

  const toggleFullscreen = async () => {
    const root = document.documentElement;
    if (!document.fullscreenElement) {
      await root.requestFullscreen?.();
    } else {
      await document.exitFullscreen?.();
    }
  };

  const sendPointer = (action: number, clientX: number, clientY: number) => {
    const el = surfaceRef.current;
    if (!el || !viewerRef.current) return;
    const { x, y } = normalizedPointer(
      el,
      clientX,
      clientY,
      mediaAspectRef.current
    );
    viewerRef.current.sendInput({ type: "pointer", x, y, action });
  };

  const onTouch = (e: React.TouchEvent) => {
    e.preventDefault();
    const t = e.changedTouches[0];
    if (!t) return;
    const action = e.type === "touchstart" ? 1 : e.type === "touchend" ? 2 : 0;
    sendPointer(action, t.clientX, t.clientY);
  };

  const onMouse = (e: React.MouseEvent) => {
    const action =
      e.button === 2
        ? e.type === "mousedown"
          ? 3
          : e.type === "mouseup"
            ? 4
            : 0
        : e.type === "mousedown"
          ? 1
          : e.type === "mouseup"
            ? 2
            : 0;
    if (action) sendPointer(action, e.clientX, e.clientY);
  };

  const onWheel = (e: React.WheelEvent) => {
    e.preventDefault();
    viewerRef.current?.sendWheel(e.deltaX, e.deltaY);
  };

  const connected = state === "connected";
  const busy =
    state === "connecting" ||
    state === "registering" ||
    state === "waiting_host" ||
    state === "negotiating";

  useEffect(() => {
    if (!connected) return;
    const shouldIgnore = (e: KeyboardEvent) => {
      const t = e.target;
      return t instanceof HTMLInputElement || t instanceof HTMLTextAreaElement;
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if (shouldIgnore(e)) return;
      e.preventDefault();
      viewerRef.current?.sendKey(e.key, true);
    };
    const onKeyUp = (e: KeyboardEvent) => {
      if (shouldIgnore(e)) return;
      e.preventDefault();
      viewerRef.current?.sendKey(e.key, false);
    };
    window.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("keyup", onKeyUp, true);
    return () => {
      window.removeEventListener("keydown", onKeyDown, true);
      window.removeEventListener("keyup", onKeyUp, true);
    };
  }, [connected]);

  return (
    <div className="app">
      {!connected ? (
        <section className="panel connect-panel">
          <h1>Rohomieo</h1>
          <p className="hint">
            Scan the QR in the <strong>rohomieo-host</strong> window on your PC,
            or open <code>https://YOUR-LAPTOP-IP:8443</code> and enter Session +
            PIN (accept the certificate warning once).
          </p>
          <label>
            Signaling WebSocket
            <input
              value={signalingUrl}
              onChange={(e) => setSignalingUrl(e.target.value)}
              placeholder="wss://10.8.0.20:8443/ws"
            />
          </label>
          <label>
            Session ID
            <input
              value={sessionId}
              onChange={(e) => setSessionId(e.target.value)}
              placeholder="from host terminal"
            />
          </label>
          <label>
            PIN
            <input
              value={pin}
              onChange={(e) => setPin(e.target.value)}
              placeholder="6 digits"
              inputMode="numeric"
            />
          </label>
          <label className="checkbox">
            <input
              type="checkbox"
              checked={remember}
              onChange={(e) => setRemember(e.target.checked)}
            />
            Remember session on this device
          </label>
          <div className="actions">
            <button
              type="button"
              className="primary"
              onClick={connect}
              disabled={busy}
            >
              {busy ? "Working…" : "Connect"}
            </button>
          </div>
          <p className="status" role="status">
            <strong>{statusLabel(state)}</strong>
            {detail ? ` — ${detail}` : ""}
          </p>
        </section>
      ) : (
        <section className={`viewer${fullscreen ? " is-fullscreen" : ""}`}>
          <video ref={videoRef} autoPlay playsInline muted />
          <img
            ref={frameRef}
            className="frame-fallback"
            alt=""
            style={{ display: "none" }}
          />
          <div
            ref={surfaceRef}
            className="touch-surface"
            onTouchStart={onTouch}
            onTouchMove={onTouch}
            onTouchEnd={onTouch}
            onMouseDown={onMouse}
            onMouseUp={onMouse}
            onMouseMove={(e) => {
              if (e.buttons) sendPointer(0, e.clientX, e.clientY);
            }}
            onContextMenu={(e) => e.preventDefault()}
            onWheel={onWheel}
          />
          <div className="toolbar">
            <button type="button" onClick={() => setKeyboardOpen(!keyboardOpen)}>
              Keyboard
            </button>
            <button type="button" onClick={toggleFullscreen}>
              {fullscreen ? "Exit fullscreen" : "Fullscreen"}
            </button>
            <button type="button" onClick={disconnect}>
              Disconnect
            </button>
          </div>
          {keyboardOpen && (
            <div className="osk">
              <input
                autoFocus
                enterKeyHint="send"
                value={typed}
                onChange={(e) => {
                  const next = e.target.value;
                  const prev = typed;
                  if (next.length > prev.length) {
                    const added = next.slice(prev.length);
                    for (const ch of added) {
                      viewerRef.current?.sendKey(ch, true);
                      viewerRef.current?.sendKey(ch, false);
                    }
                  } else if (next.length < prev.length) {
                    for (let i = 0; i < prev.length - next.length; i++) {
                      viewerRef.current?.sendKey("Backspace", true);
                      viewerRef.current?.sendKey("Backspace", false);
                    }
                  }
                  setTyped(next);
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    viewerRef.current?.sendKey("Enter", true);
                    viewerRef.current?.sendKey("Enter", false);
                    setTyped("");
                    e.preventDefault();
                  }
                }}
              />
              <button
                type="button"
                onClick={() => {
                  viewerRef.current?.sendKey("Enter", true);
                  viewerRef.current?.sendKey("Enter", false);
                  setTyped("");
                }}
              >
                Send
              </button>
            </div>
          )}
        </section>
      )}
    </div>
  );
}

function statusLabel(state: ConnectionState): string {
  switch (state) {
    case "connecting":
      return "Connecting to signaling…";
    case "registering":
      return "Registering…";
    case "waiting_host":
      return "Waiting for host";
    case "negotiating":
      return "Starting video…";
    case "connected":
      return "Connected";
    case "error":
      return "Error";
    default:
      return state;
  }
}
