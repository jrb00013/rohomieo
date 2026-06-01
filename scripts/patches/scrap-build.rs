// Patched build.rs: cross-compile scrap to Windows from Linux/WSL (no MSVC).

fn main() {
    let target = std::env::var("TARGET").unwrap_or_default();
    if target.contains("windows") {
        println!("cargo:rustc-cfg=dxgi");
    } else if target.contains("apple") {
        println!("cargo:rustc-cfg=quartz");
    } else if std::env::var("HOST").map(|h| h.contains("windows")).unwrap_or(false) {
        println!("cargo:rustc-cfg=dxgi");
    } else if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        println!("cargo:rustc-cfg=quartz");
    } else {
        println!("cargo:rustc-cfg=x11");
    }
}
