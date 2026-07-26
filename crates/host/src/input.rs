use anyhow::Result;
use enigo::{Axis, Button, Coordinate, Direction, Enigo, Key, Keyboard, Mouse, Settings};
use rohomieo_proto::InputEvent;
use tracing::{info, warn};

pub struct InputInjector {
    enigo: Enigo,
    /// Screen size in the coordinate space Enigo Absolute mouse uses (logical DPI).
    mouse_w: i32,
    mouse_h: i32,
}

impl InputInjector {
    pub fn new(_capture_w: i32, _capture_h: i32) -> Result<Self> {
        let enigo = Enigo::new(&Settings::default())?;
        // scrap/DXGI is often physical pixels; Enigo Absolute uses GetSystemMetrics
        // (logical). Mixing them makes touch look "not 1:1" on scaled displays.
        let (mouse_w, mouse_h) = enigo.main_display()?;
        info!("input mouse space {mouse_w}x{mouse_h} (capture was {_capture_w}x{_capture_h})");
        Ok(Self {
            enigo,
            mouse_w,
            mouse_h,
        })
    }

    pub fn update_dimensions(&mut self, _w: i32, _h: i32) {
        if let Ok((w, h)) = self.enigo.main_display() {
            self.mouse_w = w;
            self.mouse_h = h;
        }
    }

    pub fn handle(&mut self, event: InputEvent) {
        if let Err(e) = self.handle_inner(event) {
            warn!("input: {e}");
        }
    }

    fn handle_inner(&mut self, event: InputEvent) -> Result<()> {
        match event {
            InputEvent::Pointer { x, y, action } => {
                let px = (x.clamp(0.0, 1.0) * (self.mouse_w.saturating_sub(1)) as f64).round()
                    as i32;
                let py = (y.clamp(0.0, 1.0) * (self.mouse_h.saturating_sub(1)) as f64).round()
                    as i32;
                self.enigo.move_mouse(px, py, Coordinate::Abs)?;
                match action {
                    1 => self.enigo.button(Button::Left, Direction::Press)?,
                    2 => self.enigo.button(Button::Left, Direction::Release)?,
                    3 => self.enigo.button(Button::Right, Direction::Press)?,
                    4 => self.enigo.button(Button::Right, Direction::Release)?,
                    _ => {}
                }
            }
            InputEvent::Key { key, down } => {
                if let Some(k) = map_key(&key) {
                    let dir = if down {
                        Direction::Press
                    } else {
                        Direction::Release
                    };
                    self.enigo.key(k, dir)?;
                }
            }
            InputEvent::Wheel { delta_x, delta_y } => {
                if delta_y.abs() > delta_x.abs() {
                    let scroll = if delta_y > 0.0 { -1 } else { 1 };
                    self.enigo.scroll(scroll, Axis::Vertical)?;
                } else {
                    let scroll = if delta_x > 0.0 { -1 } else { 1 };
                    self.enigo.scroll(scroll, Axis::Horizontal)?;
                }
            }
        }
        Ok(())
    }
}

fn map_key(key: &str) -> Option<Key> {
    match key {
        "Enter" => Some(Key::Return),
        "Backspace" => Some(Key::Backspace),
        "Tab" => Some(Key::Tab),
        "Escape" => Some(Key::Escape),
        "Delete" | "Del" => Some(Key::Delete),
        "ArrowUp" => Some(Key::UpArrow),
        "ArrowDown" => Some(Key::DownArrow),
        "ArrowLeft" => Some(Key::LeftArrow),
        "ArrowRight" => Some(Key::RightArrow),
        "Home" => Some(Key::Home),
        "End" => Some(Key::End),
        "PageUp" => Some(Key::PageUp),
        "PageDown" => Some(Key::PageDown),
        " " => Some(Key::Space),
        "Shift" | "ShiftLeft" | "ShiftRight" => Some(Key::Shift),
        "Control" | "ControlLeft" | "ControlRight" => Some(Key::Control),
        "Alt" | "AltLeft" | "AltRight" => Some(Key::Alt),
        "Meta" | "MetaLeft" | "MetaRight" | "OS" => Some(Key::Meta),
        s if s.len() == 1 => {
            let c = s.chars().next()?;
            Some(Key::Unicode(c))
        }
        _ => None,
    }
}
