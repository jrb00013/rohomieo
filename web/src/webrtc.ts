import { InputEvent, send, SignalMessage } from "./proto";

export type ConnectionState =
  | "disconnected"
  | "connecting"
  | "waiting_host"
  | "negotiating"
  | "connected"
  | "error";

export interface ViewerCallbacks {
  onState: (s: ConnectionState, detail?: string) => void;
  onVideo: (stream: MediaStream) => void;
}

export class RohomieoViewer {
  private ws: WebSocket | null = null;
  private pc: RTCPeerConnection | null = null;
  private dc: RTCDataChannel | null = null;
  private heartbeatTimer: number | null = null;

  constructor(private cb: ViewerCallbacks) {}

  connect(signalingUrl: string, sessionId: string, pin: string) {
    this.cleanup();
    this.cb.onState("connecting");
    const ws = new WebSocket(signalingUrl);
    this.ws = ws;

    ws.onopen = () => {
      send(ws, { type: "register_viewer", session_id: sessionId, pin });
      this.startHeartbeat(ws);
    };

    ws.onmessage = async (ev) => {
      const msg = JSON.parse(ev.data as string) as SignalMessage;
      await this.handleSignal(msg);
    };

    ws.onerror = () => this.cb.onState("error", "WebSocket failed");
    ws.onclose = () => this.cb.onState("disconnected");
  }

  disconnect() {
    this.cleanup();
    this.cb.onState("disconnected");
  }

  private cleanup() {
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
      this.dc = ev.channel;
      this.dc.onopen = () => this.cb.onState("connected", "input ready");
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
