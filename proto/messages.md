# Rohomieo wire protocol

See `crates/proto/src/lib.rs` for the canonical Rust types. JSON uses `snake_case` for `type` discriminators.

## Signaling (WebSocket `/ws`)

| Message | Direction | Fields |
|---------|-----------|--------|
| `register_host` | host → server | `session_id`, `pin`, `device_name?` |
| `register_viewer` | viewer → server | `session_id`, `pin` |
| `registered` | server → client | `role`, `session_id` |
| `offer` / `answer` | either peer via server | `sdp` |
| `ice_candidate` | either | `candidate`, `sdpMid?`, `sdpMLineIndex?` |
| `heartbeat` | either | — |
| `peer_joined` / `peer_left` | server → client | `role` |

WebRTC media never transits the signaling server.

## DataChannel (`input`)

| Event | Fields |
|-------|--------|
| `pointer` | `x`, `y` (0–1), `action` (0=move, 1=L down, 2=L up, 3=R down, 4=R up) |
| `key` | `key`, `down` |
| `wheel` | `delta_x`, `delta_y` |
