//! Per-OS setup hints (capture/input are handled by `scrap` + `enigo` via cfg).

#[cfg(target_os = "linux")]
pub fn print_setup_hints() {
    eprintln!("Linux: install libx11-dev libxcb1-dev libxdo-dev if link fails");
    eprintln!("Wayland-only sessions may need an X11 session or PipeWire portal (future)");
}

#[cfg(target_os = "windows")]
pub fn print_setup_hints() {
    eprintln!("Windows: run host on the desktop session you want to share");
}

#[cfg(target_os = "macos")]
pub fn print_setup_hints() {
    crate::capture::macos_permission_hint();
    eprintln!("macOS: enable Accessibility for input injection in Privacy settings");
}

#[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
pub fn print_setup_hints() {}
