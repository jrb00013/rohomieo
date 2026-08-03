import { HostEvent, InputEvent, send, SignalMessage } from "./proto";

export type ConnectionState =
  | "disconnected"
  | "connecting"
  | "registering"
  | "waiting_host"
  | "negotiating"
  | "connected"
  | "error";

export interface ViewerCallbacks {
  onState: (s: ConnectionState, detail?: string) => void;
  onVideo: (stream: MediaStream) => void;
  /** JPEG frames over the "frames" datachannel (phone-friendly fallback). */
  onFrame?: (url: string) => void;
  /** Host says a remote text field has (or lost) focus — raise soft keyboard. */
  onTextFocus?: (focused: boolean) => void;
}

const SESSION_NOT_FOUND_RETRIES = 8;
const SESSION_NOT_FOUND_DELAY_MS = 750;

export class RohomieoViewer {
  private ws: WebSocket | null = null;
  private pc: RTCPeerConnection | null = null;
  private dc: RTCDataChannel | null = null;
  private frameUrl: string | null = null;
  private heartbeatTimer: number | null = null;
  private connectTimer: number | null = null;
  private sessionRetryTimer: number | null = null;
  private sessionRetries = 0;
  private pendingRegister: { sid: string; pin: string } | null = null;
  private turn: { url: string; user: string; pass: string } | null = null;

  constructor(private cb: ViewerCallbacks) {}

  setTurn(turn: { url: string; user: string; pass: string } | null) {
    this.turn = turn;
  }

  connect(signalingUrl: string, sessionId: string, pin: string) {
    this.cleanup();
    this.sessionRetries = 0;
    const url = signalingUrl.trim();
    const sid = sessionId.trim().replace(/\s+/g, "");
    const pinCode = pin.trim().replace(/\D/g, "").slice(0, 6);
    this.pendingRegister = { sid, pin: pinCode };

    if (typeof window !== "undefined" && window.location.protocol === "https:" && url.startsWith("ws://")) {
      this.cb.onState(
        "error",
        "Use wss:// (not ws://) — this page is HTTPS"
      );
      return;
    }

    if (!sid || pinCode.length < 4) {
      this.cb.onState("error", "Session ID and PIN are required");
      return;
    }

    this.cb.onState("connecting", `Opening ${url}`);
    const ws = new WebSocket(url);
    this.ws = ws;

    this.connectTimer = window.setTimeout(() => {
      if (ws.readyState === WebSocket.CONNECTING) {
        ws.close();
        this.cb.onState(
          "error",
          "Timed out reaching signaling. On the phone: open https://YOUR-PC-IP:8443 first, accept the security warning, then connect. Ensure the host window is open on the laptop."
        );
      }
    }, 12_000);

    ws.onopen = () => {
      if (this.connectTimer) clearTimeout(this.connectTimer);
      this.connectTimer = null;
      this.cb.onState("registering", "Checking session and PIN…");
      this.sendViewerRegister(ws);
      this.startHeartbeat(ws);
    };

    ws.onmessage = async (ev) => {
      try {
        const msg = JSON.parse(ev.data as string) as SignalMessage;
        await this.handleSignal(msg);
      } catch (e) {
        this.cb.onState("error", `Bad message from server: ${e}`);
      }
    };

    ws.onerror = () => {
      if (this.connectTimer) clearTimeout(this.connectTimer);
      this.cb.onState(
        "error",
        "WebSocket failed — wrong URL or certificate not trusted. Visit https://your-laptop-ip:8443 in Safari/Chrome first and tap Advanced → Proceed."
      );
    };
    ws.onclose = (ev) => {
      if (this.connectTimer) clearTimeout(this.connectTimer);
      if (ev.code !== 1000 && this.ws === ws) {
        this.cb.onState(
          "error",
          ev.reason || `Connection closed (code ${ev.code})`
        );
      } else if (this.ws === ws) {
        this.cb.onState("disconnected");
      }
    };
  }

  private sendViewerRegister(ws: WebSocket) {
    const pending = this.pendingRegister;
    if (!pending || ws.readyState !== WebSocket.OPEN) return;
    send(ws, {
      type: "register_viewer",
      session_id: pending.sid,
      pin: pending.pin,
    });
  }

  disconnect() {
    this.cleanup();
    this.cb.onState("disconnected");
  }

  private cleanup() {
    if (this.frameUrl) URL.revokeObjectURL(this.frameUrl);
    this.frameUrl = null;
    if (this.connectTimer) clearTimeout(this.connectTimer);
    this.connectTimer = null;
    if (this.sessionRetryTimer) clearTimeout(this.sessionRetryTimer);
    this.sessionRetryTimer = null;
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = null;
    this.dc?.close();
    this.pc?.close();
    this.ws?.close();
    this.dc = null;
    this.pc = null;
    this.ws = null;
  }

  private startHeartbeat(ws: WebSocket) {
    this.heartbeatTimer = window.setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) send(ws, { type: "heartbeat" });
    }, 15000);
  }

  private async ensurePeer(): Promise<RTCPeerConnection> {
    if (this.pc) return this.pc;
    const iceServers: RTCIceServer[] = [
      {
        urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"],
      },
    ];
    if (this.turn) {
      const urls = [this.turn.url];
      if (!/transport=tcp/i.test(this.turn.url)) {
        urls.push(
          this.turn.url.includes("?")
            ? `${this.turn.url}&transport=tcp`
            : `${this.turn.url}?transport=tcp`
        );
      }
      iceServers.push({
        urls,
        username: this.turn.user,
        credential: this.turn.pass,
      });
    }
    const pc = new RTCPeerConnection({ iceServers });
    this.pc = pc;

    pc.ontrack = (ev) => {
      const stream =
        ev.streams[0] ?? new MediaStream(ev.track ? [ev.track] : []);
      this.cb.onState("connected");
      this.cb.onVideo(stream);
    };

    pc.onicecandidate = (ev) => {
      if (ev.candidate && this.ws?.readyState === WebSocket.OPEN) {
        send(this.ws, {
          type: "ice_candidate",
          candidate: ev.candidate.candidate,
          sdpMid: ev.candidate.sdpMid,
          sdpMLineIndex: ev.candidate.sdpMLineIndex ?? undefined,
        });
      }
    };

    pc.ondatachannel = (ev) => {
      const ch = ev.channel;
      if (ch.label === "frames") {
        ch.binaryType = "arraybuffer";
        ch.onmessage = (e) => {
          void (async () => {
            let data: ArrayBuffer | null = null;
            if (e.data instanceof ArrayBuffer) data = e.data;
            else if (e.data instanceof Blob) data = await e.data.arrayBuffer();
            else if (ArrayBuffer.isView(e.data)) {
              const v = e.data as ArrayBufferView;
              data = v.buffer.slice(v.byteOffset, v.byteOffset + v.byteLength) as ArrayBuffer;
            }
            if (!data || data.byteLength < 100) return;
            const blob = new Blob([data], { type: "image/jpeg" });
            const url = URL.createObjectURL(blob);
            if (this.frameUrl) URL.revokeObjectURL(this.frameUrl);
            this.frameUrl = url;
            this.cb.onFrame?.(url);
            this.cb.onState("connected");
          })();
        };
        return;
      }
      if (ch.label === "input") {
        this.dc = ch;
        ch.onopen = () => this.cb.onState("connected", "ready");
        ch.onmessage = (e) => {
          try {
            const raw =
              typeof e.data === "string"
                ? e.data
                : new TextDecoder().decode(e.data as ArrayBuffer);
            const msg = JSON.parse(raw) as HostEvent;
            if (msg?.type === "text_focus") {
              this.cb.onTextFocus?.(!!msg.focused);
            }
          } catch {
            /* ignore non-JSON */
          }
        };
      }
    };

    return pc;
  }

  private async handleSignal(msg: SignalMessage) {
    switch (msg.type) {
      case "registered":
        this.sessionRetries = 0;
        this.cb.onState("waiting_host");
        break;
      case "error": {
        const text = msg.message || "";
        const notReady =
          /session not found|not connected to signaling/i.test(text);
        if (
          notReady &&
          this.ws?.readyState === WebSocket.OPEN &&
          this.sessionRetries < SESSION_NOT_FOUND_RETRIES
        ) {
          this.sessionRetries += 1;
          this.cb.onState(
            "registering",
            `Waiting for host… (${this.sessionRetries}/${SESSION_NOT_FOUND_RETRIES})`
          );
          if (this.sessionRetryTimer) clearTimeout(this.sessionRetryTimer);
          this.sessionRetryTimer = window.setTimeout(() => {
            if (this.ws) this.sendViewerRegister(this.ws);
          }, SESSION_NOT_FOUND_DELAY_MS);
          break;
        }
        this.cb.onState("error", text);
        break;
      }
      case "offer": {
        this.cb.onState("negotiating");
        const pc = await this.ensurePeer();
        await pc.setRemoteDescription({ type: "offer", sdp: msg.sdp });
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        if (this.ws) send(this.ws, { type: "answer", sdp: answer.sdp! });
        break;
      }
      case "ice_candidate":
        if (this.pc) {
          await this.pc.addIceCandidate({
            candidate: msg.candidate,
            sdpMid: msg.sdpMid ?? undefined,
            sdpMLineIndex: msg.sdpMLineIndex ?? undefined,
          });
        }
        break;
      case "peer_left":
        this.cb.onState("waiting_host", "Host disconnected");
        break;
    }
  }

  sendInput(evt: InputEvent) {
    if (this.dc?.readyState === "open") {
      this.dc.send(JSON.stringify(evt));
      return;
    }
    // Channel can lag a beat behind "connected" from JPEG/video.
    if (this.dc && this.dc.readyState === "connecting") {
      const ch = this.dc;
      const payload = JSON.stringify(evt);
      const sendOnce = () => ch.send(payload);
      ch.addEventListener("open", sendOnce, { once: true });
    }
  }

  sendKey(key: string, down: boolean) {
    this.sendInput({ type: "key", key, down });
  }

  sendWheel(deltaX: number, deltaY: number) {
    this.sendInput({ type: "wheel", delta_x: deltaX, delta_y: deltaY });
  }
}

export function normalizedPointer(
  el: HTMLElement,
  clientX: number,
  clientY: number,
  mediaAspect?: number
): { x: number; y: number } {
  const r = el.getBoundingClientRect();
  const clamp = (v: number) => Math.min(1, Math.max(0, v));
  if (!mediaAspect || !(mediaAspect > 0) || r.width <= 0 || r.height <= 0) {
    return {
      x: clamp((clientX - r.left) / r.width),
      y: clamp((clientY - r.top) / r.height),
    };
  }
  // Match CSS object-fit: contain letterboxing so taps land on the real desktop.
  const viewAspect = r.width / r.height;
  let contentW = r.width;
  let contentH = r.height;
  let offX = 0;
  let offY = 0;
  if (viewAspect > mediaAspect) {
    contentW = r.height * mediaAspect;
    offX = (r.width - contentW) / 2;
  } else {
    contentH = r.width / mediaAspect;
    offY = (r.height - contentH) / 2;
  }
  return {
    x: clamp((clientX - r.left - offX) / contentW),
    y: clamp((clientY - r.top - offY) / contentH),
  };
}
