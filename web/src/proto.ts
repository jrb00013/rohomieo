/** Mirrors crates/proto — signaling + input events */

export type Role = "host" | "viewer";

export type SignalMessage =
  | { type: "register_host"; session_id: string; pin: string; device_name?: string }
  | { type: "register_viewer"; session_id: string; pin: string }
  | { type: "registered"; role: Role; session_id: string }
  | { type: "error"; message: string }
  | { type: "offer"; sdp: string }
  | { type: "answer"; sdp: string }
  | {
      type: "ice_candidate";
      candidate: string;
      sdpMid?: string | null;
      sdpMLineIndex?: number | null;
    }
  | { type: "heartbeat" }
  | { type: "pong" }
  | { type: "peer_joined"; role: Role }
  | { type: "peer_left" };

export type InputEvent =
  | { type: "pointer"; x: number; y: number; action: number }
  | { type: "key"; key: string; down: boolean }
  | { type: "wheel"; delta_x: number; delta_y: number };

export function send(ws: WebSocket, msg: SignalMessage) {
  ws.send(JSON.stringify(msg));
}
