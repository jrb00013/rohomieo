import { useCallback, useEffect, useRef, useState } from "react";
import { ConnectionState, normalizedPointer, RohomieoViewer } from "./webrtc";
import "./App.css";

const DEFAULT_WS =
  typeof location !== "undefined" && location.port === "5173"
    ? `${location.protocol === "https:" ? "wss" : "ws"}://${location.hostname}:8443/ws`
    : `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws`;

export default function App() {
  const [signalingUrl, setSignalingUrl] = useState(DEFAULT_WS);
  const [sessionId, setSessionId] = useState("");
  const [pin, setPin] = useState("");
  const [state, setState] = useState<ConnectionState>("disconnected");
  const [detail, setDetail] = useState("");
  const [keyboardOpen, setKeyboardOpen] = useState(false);
  const [typed, setTyped] = useState("");

  const videoRef = useRef<HTMLVideoElement>(null);
  const frameRef = useRef<HTMLImageElement>(null);
  const surfaceRef = useRef<HTMLDivElement>(null);
  const viewerRef = useRef<RohomieoViewer | null>(null);

  useEffect(() => {
    const v = viewerRef.current;
    return () => v?.disconnect();
  }, []);

  const connect = useCallback(() => {
    if (!sessionId.trim() || !pin.trim()) {
      setDetail("Enter session ID and PIN from the host");
      return;
    }
    const viewer = new RohomieoViewer({
      onState: (s, d) => {
        setState(s);
        if (d) setDetail(d);
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
          img.src = url;
          img.style.display = "block";
        }
        if (videoRef.current) videoRef.current.style.display = "none";
      },
    });
    viewerRef.current = viewer;
    viewer.connect(signalingUrl, sessionId.trim(), pin.trim());
  }, [signalingUrl, sessionId, pin]);

  const disconnect = () => viewerRef.current?.disconnect();

  const sendPointer = (action: number, clientX: number, clientY: number) => {
    const el = surfaceRef.current;
    if (!el || !viewerRef.current) return;
    const { x, y } = normalizedPointer(el, clientX, clientY);
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
      e.type === "mousedown" ? 1 : e.type === "mouseup" ? 2 : 0;
    sendPointer(action, e.clientX, e.clientY);
  };

  const flushKey = (text: string) => {
    for (const ch of text) {
      viewerRef.current?.sendKey(ch, true);
      viewerRef.current?.sendKey(ch, false);
    }
    setTyped("");
  };

  const connected = state === "connected";

  return (
    <div className="app">
      {!connected ? (
        <section className="panel connect-panel">
          <h1>Rohomieo</h1>
          <p className="hint">
            Connect WireGuard first, then open this page on your VPN IP (e.g.{" "}
            <code>https://10.8.0.20:8443</code>).
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
          <div className="actions">
            <button type="button" className="primary" onClick={connect}>
              Connect
            </button>
          </div>
          <p className="status">
            {state}
            {detail ? ` — ${detail}` : ""}
          </p>
        </section>
      ) : (
        <section className="viewer">
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
          />
          <div className="toolbar">
            <button type="button" onClick={() => setKeyboardOpen(!keyboardOpen)}>
              Keyboard
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
                onChange={(e) => setTyped(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    flushKey(typed);
                    e.preventDefault();
                  }
                }}
              />
              <button type="button" onClick={() => flushKey(typed)}>
                Send
              </button>
            </div>
          )}
        </section>
      )}
    </div>
  );
}
