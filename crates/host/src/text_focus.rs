//! Detect when a remote Windows text field has focus so the phone can raise
//! its soft keyboard.

#[cfg(windows)]
mod win {
    use std::mem::size_of;

    const GUI_CARETBLINKING: u32 = 0x0000_0001;

    #[repr(C)]
    struct Rect {
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    }

    #[repr(C)]
    struct GuiThreadInfo {
        cb_size: u32,
        flags: u32,
        hwnd_active: isize,
        hwnd_focus: isize,
        hwnd_capture: isize,
        hwnd_menu_owner: isize,
        hwnd_move_size: isize,
        hwnd_caret: isize,
        rc_caret: Rect,
    }

    #[link(name = "user32")]
    extern "system" {
        fn GetForegroundWindow() -> isize;
        fn GetWindowThreadProcessId(hwnd: isize, lpdw_process_id: *mut u32) -> u32;
        fn GetGUIThreadInfo(id_thread: u32, pgui: *mut GuiThreadInfo) -> i32;
        fn GetClassNameW(hwnd: isize, lp_class_name: *mut u16, n_max_count: i32) -> i32;
    }

    fn class_name(hwnd: isize) -> String {
        if hwnd == 0 {
            return String::new();
        }
        let mut buf = [0u16; 256];
        let n = unsafe { GetClassNameW(hwnd, buf.as_mut_ptr(), buf.len() as i32) };
        if n <= 0 {
            return String::new();
        }
        String::from_utf16_lossy(&buf[..n as usize])
    }

    fn class_looks_editable(class: &str) -> bool {
        let c = class.to_ascii_lowercase();
        c == "edit"
            || c.starts_with("richedit")
            || c == "textbox"
            || c == "textfield"
            || c == "formfield"
            || c.contains("editcontrol")
            || c == "windows.ui.input.inputsite.windowclass"
    }

    pub fn is_text_input_focused() -> bool {
        unsafe {
            let fg = GetForegroundWindow();
            if fg == 0 {
                return false;
            }
            let tid = GetWindowThreadProcessId(fg, std::ptr::null_mut());
            if tid == 0 {
                return false;
            }
            let mut info = GuiThreadInfo {
                cb_size: size_of::<GuiThreadInfo>() as u32,
                flags: 0,
                hwnd_active: 0,
                hwnd_focus: 0,
                hwnd_capture: 0,
                hwnd_menu_owner: 0,
                hwnd_move_size: 0,
                hwnd_caret: 0,
                rc_caret: Rect {
                    left: 0,
                    top: 0,
                    right: 0,
                    bottom: 0,
                },
            };
            if GetGUIThreadInfo(tid, &mut info) == 0 {
                return false;
            }
            if info.hwnd_caret != 0 || (info.flags & GUI_CARETBLINKING) != 0 {
                return true;
            }
            class_looks_editable(&class_name(info.hwnd_focus))
        }
    }
}

#[cfg(windows)]
pub use win::is_text_input_focused;

#[cfg(not(windows))]
pub fn is_text_input_focused() -> bool {
    false
}
