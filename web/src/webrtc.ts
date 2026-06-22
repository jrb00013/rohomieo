import { InputEvent, send, SignalMessage } from "./proto";

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
}

export class RohomieoViewer {
  private ws: WebSocket | null = null;
  private pc: RTCPeerConnection | null = null;
  private dc: RTCDataChannel | null = null;
  private frameUrl: string | null = null;
  private heartbeatTimer: number | null = null;
  private connectTimer: number | null = null;

  constructor(private cb: ViewerCallbacks) {}

  connect(signalingUrl: string, sessionId: string, pin: string) {
    this.cleanup();
    const url = signalingUrl.trim();
    const sid = sessionId.trim().replace(/\s+/g, "");
    const pinCode = pin.trim().replace(/\D/g, "").slice(0, 6);

    if (typeof window !== "undefined" && window.location.protocol === "https:" && url.startsWith("ws://")) {
      this.cb.onState(
        "error",
        "Use wss:// (not ws://) — this page is HTTPS"
      );
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
      send(ws, { type: "register_viewer", session_id: sid, pin: pinCode });
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
      } else {
        this.cb.onState("disconnected");
      }
    };
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
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
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
    const pc = new RTCPeerConnection({
      iceServers: [],
    });
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
          const data = e.data;
          if (!(data instanceof ArrayBuffer)) return;
          const blob = new Blob([data], { type: "image/jpeg" });
          const url = URL.createObjectURL(blob);
          if (this.frameUrl) URL.revokeObjectURL(this.frameUrl);
          this.frameUrl = url;
          this.cb.onFrame?.(url);
          this.cb.onState("connected");
        };
        return;
      }
      if (ch.label === "input") {
        this.dc = ch;
        ch.onopen = () => this.cb.onState("connected", "ready");
      }
    };

    return pc;
  }

  private async handleSignal(msg: SignalMessage) {
    switch (msg.type) {
      case "registered":
        this.cb.onState("waiting_host");
        break;
      case "error":
        this.cb.onState("error", msg.message);
        break;
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
  clientY: number
): { x: number; y: number } {
  const r = el.getBoundingClientRect();
  return {
    x: (clientX - r.left) / r.width,
    y: (clientY - r.top) / r.height,
  };
}
