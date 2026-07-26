import { useCallback, useEffect, useRef, useState } from "react";
import { ConnectionState, RohomieoViewer } from "./webrtc";
import { loadSession, saveSession } from "./storage";
import "./App.css";

const DEFAULT_WS =
  typeof location !== "undefined" && location.port === "5173"
    ? `${location.protocol === "https:" ? "wss" : "ws"}://${location.hostname}:8443/ws`
    : `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws`;

const ZOOM_MIN = 1;
const ZOOM_MAX = 4;
const ZOOM_STEP = 0.35;

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

function clamp(n: number, lo: number, hi: number) {
  return Math.min(hi, Math.max(lo, n));
}

/** Desktop 0–1 coords from a tap, using the transformed stage's on-screen box (1:1 with pixels). */
function pointerOnStage(
  stage: HTMLElement,
  clientX: number,
  clientY: number
): { x: number; y: number } | null {
  const r = stage.getBoundingClientRect();
  if (r.width < 2 || r.height < 2) return null;
  const x = (clientX - r.left) / r.width;
  const y = (clientY - r.top) / r.height;
  if (x < -0.02 || x > 1.02 || y < -0.02 || y > 1.02) return null;
  return { x: clamp(x, 0, 1), y: clamp(y, 0, 1) };
}

export default function App() {
  const invite = readInviteFromUrl();
  const saved = loadSession();
  const initialWs =
    invite.signalingUrl ??
    (invite.sessionId || invite.auto
      ? DEFAULT_WS
      : saved.signalingUrl ?? DEFAULT_WS);
  const [signalingUrl, setSignalingUrl] = useState(() => {
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
  const [zoom, setZoom] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const [mediaAspect, setMediaAspect] = useState(16 / 10);
  const autoStarted = useRef(false);

  const videoRef = useRef<HTMLVideoElement>(null);
  const frameRef = useRef<HTMLImageElement>(null);
  const viewportRef = useRef<HTMLDivElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const viewerRef = useRef<RohomieoViewer | null>(null);
  const oskRef = useRef<HTMLInputElement>(null);
  const typedRef = useRef("");
  const oskComposingRef = useRef(false);
  const textFocusRef = useRef(false);
  const softKeyTimerRef = useRef<number | null>(null);
  const fingerStartRef = useRef<{ x: number; y: number } | null>(null);
  const keyboardOpenRef = useRef(false);

  const zoomRef = useRef(zoom);
  const panRef = useRef(pan);
  zoomRef.current = zoom;
  panRef.current = pan;
  keyboardOpenRef.current = keyboardOpen;

  const pinchRef = useRef<{
    startDist: number;
    startZoom: number;
    startPan: { x: number; y: number };
    startMid: { x: number; y: number };
  } | null>(null);
  const oneFingerRef = useRef(false);

  const clearOskBuffer = useCallback(() => {
    typedRef.current = "";
    setTyped("");
    const el = oskRef.current;
    if (el && el.value) el.value = "";
  }, []);

  /** Diff previous vs next OSK text and inject only the delta (code-point safe). */
  const syncOskToRemote = useCallback((prev: string, next: string) => {
    if (prev === next) return;
    const a = [...prev];
    const b = [...next];
    let i = 0;
    while (i < a.length && i < b.length && a[i] === b[i]) i++;
    for (let k = i; k < a.length; k++) {
      viewerRef.current?.sendKey("Backspace", true);
      viewerRef.current?.sendKey("Backspace", false);
    }
    for (let k = i; k < b.length; k++) {
      viewerRef.current?.sendKey(b[k], true);
      viewerRef.current?.sendKey(b[k], false);
    }
  }, []);

  const applyOskValue = useCallback(
    (next: string) => {
      const prev = typedRef.current;
      syncOskToRemote(prev, next);
      typedRef.current = next;
      setTyped(next);
    },
    [syncOskToRemote]
  );

  const openSoftKeyboard = useCallback(() => {
    setKeyboardOpen(true);
    const el = oskRef.current;
    if (el) {
      el.focus({ preventScroll: true });
    }
  }, []);

  const closeSoftKeyboard = useCallback(() => {
    textFocusRef.current = false;
    setKeyboardOpen(false);
    clearOskBuffer();
    oskRef.current?.blur();
  }, [clearOskBuffer]);

  /** Focus during the touch gesture so iOS/Android will actually raise the keyboard. */
  const armSoftKeyboardForTap = useCallback(() => {
    // Fresh buffer so the first typed char diffs against "" (not a stale leftover).
    clearOskBuffer();
    oskRef.current?.focus({ preventScroll: true });
    if (softKeyTimerRef.current) window.clearTimeout(softKeyTimerRef.current);
    softKeyTimerRef.current = window.setTimeout(() => {
      softKeyTimerRef.current = null;
      if (!textFocusRef.current) {
        oskRef.current?.blur();
        setKeyboardOpen(false);
      }
    }, 650);
  }, [clearOskBuffer]);

  const applyHostTextFocus = useCallback(
    (focused: boolean) => {
      textFocusRef.current = focused;
      if (softKeyTimerRef.current) {
        window.clearTimeout(softKeyTimerRef.current);
        softKeyTimerRef.current = null;
      }
      if (focused) openSoftKeyboard();
      else closeSoftKeyboard();
    },
    [openSoftKeyboard, closeSoftKeyboard]
  );

  useEffect(() => {
    const v = viewerRef.current;
    return () => v?.disconnect();
  }, []);

  useEffect(() => {
    const onFs = () => setFullscreen(!!document.fullscreenElement);
    document.addEventListener("fullscreenchange", onFs);
    return () => document.removeEventListener("fullscreenchange", onFs);
  }, []);

  const layoutStage = useCallback(() => {
    const viewport = viewportRef.current;
    const stage = stageRef.current;
    if (!viewport || !stage) return;
    const vw = viewport.clientWidth;
    const vh = viewport.clientHeight;
    if (vw < 2 || vh < 2) return;
    const viewAspect = vw / vh;
    let w: number;
    let h: number;
    if (viewAspect > mediaAspect) {
      h = vh;
      w = vh * mediaAspect;
    } else {
      w = vw;
      h = vw / mediaAspect;
    }
    stage.style.width = `${w}px`;
    stage.style.height = `${h}px`;
  }, [mediaAspect]);

  useEffect(() => {
    layoutStage();
    const ro = new ResizeObserver(() => layoutStage());
    if (viewportRef.current) ro.observe(viewportRef.current);
    return () => ro.disconnect();
  }, [layoutStage, state]);

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
    setZoom(1);
    setPan({ x: 0, y: 0 });
    setKeyboardOpen(false);
    textFocusRef.current = false;
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
        el.onloadedmetadata = () => {
          if (el.videoWidth > 0 && el.videoHeight > 0) {
            setMediaAspect(el.videoWidth / el.videoHeight);
          }
        };
        void el.play().catch(() => {
          setDetail("Tap the screen if video does not start");
        });
      },
      onFrame: (url) => {
        const img = frameRef.current;
        if (img) {
          img.onload = () => {
            if (img.naturalWidth > 0 && img.naturalHeight > 0) {
              setMediaAspect(img.naturalWidth / img.naturalHeight);
            }
          };
          img.src = url;
          img.style.display = "block";
        }
        if (videoRef.current) videoRef.current.style.display = "none";
      },
      onTextFocus: applyHostTextFocus,
    });
    viewerRef.current = viewer;
    viewer.connect(signalingUrl, sessionId.trim(), pin.trim());
  }, [signalingUrl, sessionId, pin, remember, applyHostTextFocus]);

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

  const setZoomAround = (nextZoom: number, focusClientX?: number, focusClientY?: number) => {
    const viewport = viewportRef.current;
    const z0 = zoomRef.current;
    const z1 = clamp(nextZoom, ZOOM_MIN, ZOOM_MAX);
    if (!viewport || Math.abs(z1 - z0) < 0.001) {
      setZoom(z1);
      if (z1 <= 1.001) setPan({ x: 0, y: 0 });
      return;
    }
    const r = viewport.getBoundingClientRect();
    const fx = (focusClientX ?? r.left + r.width / 2) - r.left - r.width / 2;
    const fy = (focusClientY ?? r.top + r.height / 2) - r.top - r.height / 2;
    const p0 = panRef.current;
    // Keep the focus point stable under scale change (origin at viewport center).
    const p1 = {
      x: fx - ((fx - p0.x) * z1) / z0,
      y: fy - ((fy - p0.y) * z1) / z0,
    };
    setZoom(z1);
    if (z1 <= 1.001) setPan({ x: 0, y: 0 });
    else setPan(p1);
  };

  const zoomIn = () => setZoomAround(zoomRef.current + ZOOM_STEP);
  const zoomOut = () => setZoomAround(zoomRef.current - ZOOM_STEP);
  const zoomReset = () => {
    setZoom(1);
    setPan({ x: 0, y: 0 });
  };

  const sendPointer = (action: number, clientX: number, clientY: number) => {
    const stage = stageRef.current;
    if (!stage || !viewerRef.current) return;
    const pt = pointerOnStage(stage, clientX, clientY);
    if (!pt) return;
    viewerRef.current.sendInput({ type: "pointer", x: pt.x, y: pt.y, action });
  };

  const touchDist = (
    a: { clientX: number; clientY: number },
    b: { clientX: number; clientY: number }
  ) => {
    const dx = a.clientX - b.clientX;
    const dy = a.clientY - b.clientY;
    return Math.hypot(dx, dy);
  };

  const onTouchStart = (e: React.TouchEvent) => {
    e.preventDefault();
    if (e.touches.length >= 2) {
      oneFingerRef.current = false;
      fingerStartRef.current = null;
      const a = e.touches[0];
      const b = e.touches[1];
      pinchRef.current = {
        startDist: touchDist(a, b),
        startZoom: zoomRef.current,
        startPan: { ...panRef.current },
        startMid: {
          x: (a.clientX + b.clientX) / 2,
          y: (a.clientY + b.clientY) / 2,
        },
      };
      return;
    }
    pinchRef.current = null;
    oneFingerRef.current = true;
    const t = e.changedTouches[0];
    if (t) {
      fingerStartRef.current = { x: t.clientX, y: t.clientY };
      sendPointer(1, t.clientX, t.clientY);
    }
  };

  const onTouchMove = (e: React.TouchEvent) => {
    e.preventDefault();
    if (e.touches.length >= 2 && pinchRef.current) {
      const a = e.touches[0];
      const b = e.touches[1];
      const dist = touchDist(a, b);
      const midX = (a.clientX + b.clientX) / 2;
      const midY = (a.clientY + b.clientY) / 2;
      const scale = dist / Math.max(1, pinchRef.current.startDist);
      const nextZoom = clamp(
        pinchRef.current.startZoom * scale,
        ZOOM_MIN,
        ZOOM_MAX
      );
      const z0 = pinchRef.current.startZoom;
      const viewport = viewportRef.current?.getBoundingClientRect();
      if (viewport && z0 > 0) {
        const fx =
          pinchRef.current.startMid.x - viewport.left - viewport.width / 2;
        const fy =
          pinchRef.current.startMid.y - viewport.top - viewport.height / 2;
        const p0 = pinchRef.current.startPan;
        const p1 = {
          x:
            fx -
            ((fx - p0.x) * nextZoom) / z0 +
            (midX - pinchRef.current.startMid.x),
          y:
            fy -
            ((fy - p0.y) * nextZoom) / z0 +
            (midY - pinchRef.current.startMid.y),
        };
        setZoom(nextZoom);
        setPan(nextZoom <= 1.001 ? { x: 0, y: 0 } : p1);
      } else {
        setZoomAround(nextZoom, midX, midY);
      }
      return;
    }
    if (!oneFingerRef.current) return;
    const t = e.changedTouches[0];
    if (t) sendPointer(0, t.clientX, t.clientY);
  };

  const onTouchEnd = (e: React.TouchEvent) => {
    e.preventDefault();
    if (e.touches.length < 2) pinchRef.current = null;
    if (e.touches.length === 0 && oneFingerRef.current) {
      const t = e.changedTouches[0];
      if (t) {
        sendPointer(2, t.clientX, t.clientY);
        const start = fingerStartRef.current;
        const moved = start
          ? Math.hypot(t.clientX - start.x, t.clientY - start.y)
          : 0;
        // Short tap → arm soft keyboard now (user-gesture). Host confirms text field.
        if (moved < 18) armSoftKeyboardForTap();
      }
      oneFingerRef.current = false;
      fingerStartRef.current = null;
    }
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
    if (e.ctrlKey || e.metaKey) {
      const delta = e.deltaY > 0 ? -ZOOM_STEP : ZOOM_STEP;
      setZoomAround(zoomRef.current + delta, e.clientX, e.clientY);
      return;
    }
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
      // Mobile soft keyboards often fire a capture-phase keydown with
      // Unidentified/Process before the <input> is the event target. preventDefault
      // there swallows the first character; let the OSK input handle typing instead.
      if (e.isComposing || e.key === "Process" || e.key === "Unidentified") {
        return true;
      }
      if (keyboardOpenRef.current) return true;
      if (document.activeElement === oskRef.current) return true;
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
          <div ref={viewportRef} className="viewport">
            <div
              ref={stageRef}
              className="stage"
              style={{
                transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
              }}
            >
              <video ref={videoRef} autoPlay playsInline muted />
              <img
                ref={frameRef}
                className="frame-fallback"
                alt=""
                style={{ display: "none" }}
              />
            </div>
          </div>
          <div
            className="touch-surface"
            onTouchStart={onTouchStart}
            onTouchMove={onTouchMove}
            onTouchEnd={onTouchEnd}
            onTouchCancel={onTouchEnd}
            onMouseDown={onMouse}
            onMouseUp={onMouse}
            onMouseMove={(e) => {
              if (e.buttons) sendPointer(0, e.clientX, e.clientY);
            }}
            onContextMenu={(e) => e.preventDefault()}
            onWheel={onWheel}
          />
          <div className="toolbar">
            <button type="button" onClick={zoomOut} aria-label="Zoom out">
              −
            </button>
            <button type="button" onClick={zoomReset} aria-label="Reset zoom">
              {Math.round(zoom * 100)}%
            </button>
            <button type="button" onClick={zoomIn} aria-label="Zoom in">
              +
            </button>
            <button
              type="button"
              onClick={() => {
                if (keyboardOpen) closeSoftKeyboard();
                else {
                  textFocusRef.current = true;
                  openSoftKeyboard();
                }
              }}
            >
              Keyboard
            </button>
            <button type="button" onClick={toggleFullscreen}>
              {fullscreen ? "Exit" : "Full"}
            </button>
            <button type="button" onClick={disconnect}>
              Disconnect
            </button>
          </div>
          <div className={`osk${keyboardOpen ? " is-open" : " is-armed"}`}>
            <input
              ref={oskRef}
              enterKeyHint="done"
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="off"
              spellCheck={false}
              inputMode="text"
              value={typed}
              aria-label="Remote keyboard"
              onCompositionStart={() => {
                oskComposingRef.current = true;
              }}
              onCompositionEnd={(e) => {
                oskComposingRef.current = false;
                applyOskValue(e.currentTarget.value);
              }}
              onInput={(e) => {
                if (oskComposingRef.current) return;
                applyOskValue(e.currentTarget.value);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  viewerRef.current?.sendKey("Enter", true);
                  viewerRef.current?.sendKey("Enter", false);
                  clearOskBuffer();
                  e.preventDefault();
                }
              }}
              onBlur={() => {
                if (!textFocusRef.current) setKeyboardOpen(false);
              }}
            />
            {keyboardOpen && (
              <button
                type="button"
                onClick={() => {
                  viewerRef.current?.sendKey("Enter", true);
                  viewerRef.current?.sendKey("Enter", false);
                  clearOskBuffer();
                }}
              >
                Send
              </button>
            )}
          </div>
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
