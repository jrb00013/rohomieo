use anyhow::Result;
use enigo::{Axis, Button, Coordinate, Direction, Enigo, Key, Keyboard, Mouse, Settings};
use rohomieo_proto::InputEvent;
use tracing::warn;

pub struct InputInjector {
    enigo: Enigo,
    screen_w: i32,
    screen_h: i32,
}

impl InputInjector {
    pub fn new(screen_w: i32, screen_h: i32) -> Result<Self> {
        let enigo = Enigo::new(&Settings::default())?;
        Ok(Self {
            enigo,
            screen_w,
            screen_h,
        })
    }

    pub fn update_dimensions(&mut self, w: i32, h: i32) {
        self.screen_w = w;
        self.screen_h = h;
    }

    pub fn handle(&mut self, event: InputEvent) {
        if let Err(e) = self.handle_inner(event) {
            warn!("input: {e}");
        }
    }

    fn handle_inner(&mut self, event: InputEvent) -> Result<()> {
        match event {
            InputEvent::Pointer { x, y, action } => {
                let px = (x.clamp(0.0, 1.0) * self.screen_w as f64) as i32;
                let py = (y.clamp(0.0, 1.0) * self.screen_h as f64) as i32;
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
        "ArrowUp" => Some(Key::UpArrow),
        "ArrowDown" => Some(Key::DownArrow),
        "ArrowLeft" => Some(Key::LeftArrow),
        "ArrowRight" => Some(Key::RightArrow),
        " " => Some(Key::Space),
        s if s.len() == 1 => {
            let c = s.chars().next()?;
            Some(Key::Unicode(c))
        }
        _ => None,
    }
}
