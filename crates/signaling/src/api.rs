//! HTTP API handlers for status and audit export.

use crate::AppState;
use axum::{extract::State, response::IntoResponse, Json};
use serde::Serialize;

#[derive(Serialize)]
pub struct StatusResponse {
    pub status: &'static str,
    pub version: &'static str,
    pub ws_connections: usize,
    pub sessions_active: usize,
    pub audit_entries: usize,
}

pub async fn api_status(State(state): State<AppState>) -> Json<StatusResponse> {
    Json(StatusResponse {
        status: "ok",
        version: env!("CARGO_PKG_VERSION"),
        ws_connections: state.store.connection_count(),
        sessions_active: state.store.session_count(),
        audit_entries: state.audit.len(),
    })
}

pub async fn api_audit(State(state): State<AppState>) -> impl IntoResponse {
    Json(state.audit.recent(100))
}

pub async fn metrics_handler(State(state): State<AppState>) -> impl IntoResponse {
    (
        [(
            axum::http::header::CONTENT_TYPE,
            "text/plain; version=0.0.4; charset=utf-8",
        )],
        state.store.metrics().render_prometheus(),
    )
}
