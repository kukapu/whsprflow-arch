//! In-process uinput virtual keyboard (Wayland injection primitive).
//!
//! On Wayland there is no portable X11-style synthetic-input API: XTEST events
//! don't reach native Wayland surfaces. The reliable, compositor-agnostic path
//! is to create a *real* virtual input device via `/dev/uinput` and write kernel
//! key events to it -- the compositor sees them as ordinary hardware input and
//! routes them to the focused surface like any keyboard.
//!
//! This is what `ydotool` does, but in-process: we don't shell out to `ydotool`
//! (which needs its `ydotoold` daemon running). We just need write access to
//! `/dev/uinput` (typically granted to the active-session user via a logind
//! `uaccess` udev rule / ACL; otherwise the `uinput` group or root).
//!
//! Codes written here are Linux evdev `KEY_*` codes (see `keymap::vk_to_evdev`),
//! NOT X11 keysyms.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;

use super::Result;
use crate::keymap;

// --- evdev event types (<linux/input-event-codes.h>) ---
const EV_SYN: u16 = 0x00;
const EV_KEY: u16 = 0x01;
const SYN_REPORT: u16 = 0x00;

// --- uinput ioctls (<linux/uinput.h>), x86_64 encodings ---
//   UI_DEV_CREATE   = _IO('U', 1)            = 0x5501
//   UI_DEV_DESTROY  = _IO('U', 2)            = 0x5502
//   UI_SET_EVBIT    = _IOW('U', 100, int)    = 0x40045564
//   UI_SET_KEYBIT   = _IOW('U', 101, int)    = 0x40045565
const UI_DEV_CREATE: libc::c_ulong = 0x5501;
const UI_DEV_DESTROY: libc::c_ulong = 0x5502;
const UI_SET_EVBIT: libc::c_ulong = 0x40045564;
const UI_SET_KEYBIT: libc::c_ulong = 0x40045565;

const BUS_USB: u16 = 0x03;
/// We enable the full standard key range so any mapped VK can be injected.
const KEY_MAX: u16 = 0x2ff;

pub struct UInput {
    file: File,
}

impl UInput {
    /// Probe whether `/dev/uinput` is openable for writing without creating a
    /// device (used by backend detection so we can fall back gracefully).
    pub fn available() -> bool {
        OpenOptions::new()
            .write(true)
            .custom_flags(libc::O_NONBLOCK)
            .open("/dev/uinput")
            .is_ok()
    }

    /// Create the virtual keyboard. Must be kept alive for the process lifetime;
    /// dropping it destroys the device.
    pub fn create() -> Result<UInput> {
        let file = OpenOptions::new()
            .write(true)
            .custom_flags(libc::O_NONBLOCK)
            .open("/dev/uinput")
            .map_err(|e| format!("open /dev/uinput: {e} (need write access -- logind uaccess ACL, `uinput` group, or root)"))?;
        let fd = file.as_raw_fd();

        // Declare the event types and key range this device emits.
        ioctl_set(fd, UI_SET_EVBIT, EV_KEY as libc::c_int)?;
        ioctl_set(fd, UI_SET_EVBIT, EV_SYN as libc::c_int)?;
        for code in 1..=KEY_MAX {
            // Best-effort: a few codes in the range are gaps; ignore EINVAL.
            unsafe { libc::ioctl(fd, UI_SET_KEYBIT, code as libc::c_int) };
        }

        // Legacy device-setup path (write a uinput_user_dev, then UI_DEV_CREATE):
        // widely supported and avoids the newer UI_DEV_SETUP/abs_setup structs.
        let mut dev: libc::uinput_user_dev = unsafe { std::mem::zeroed() };
        let name = b"Wispr Flow Linux Helper";
        for (i, &b) in name.iter().enumerate() {
            dev.name[i] = b as libc::c_char;
        }
        dev.id.bustype = BUS_USB;
        dev.id.vendor = 0x1234;
        dev.id.product = 0x5678;
        dev.id.version = 1;

        let bytes = unsafe {
            std::slice::from_raw_parts(
                &dev as *const _ as *const u8,
                std::mem::size_of::<libc::uinput_user_dev>(),
            )
        };
        (&file)
            .write_all(bytes)
            .map_err(|e| format!("write uinput_user_dev: {e}"))?;

        if unsafe { libc::ioctl(fd, UI_DEV_CREATE) } < 0 {
            return Err(format!(
                "UI_DEV_CREATE: {}",
                std::io::Error::last_os_error()
            ));
        }

        // The compositor needs a moment to enumerate the new device before it
        // will route events from it; injecting too early drops the first keys.
        std::thread::sleep(std::time::Duration::from_millis(200));

        Ok(UInput { file })
    }

    fn emit(&mut self, type_: u16, code: u16, value: i32) -> Result<()> {
        let ev = libc::input_event {
            time: libc::timeval {
                tv_sec: 0,
                tv_usec: 0,
            },
            type_,
            code,
            value,
        };
        let bytes = unsafe {
            std::slice::from_raw_parts(
                &ev as *const _ as *const u8,
                std::mem::size_of::<libc::input_event>(),
            )
        };
        self.file
            .write_all(bytes)
            .map_err(|e| format!("uinput write: {e}"))
    }

    fn syn(&mut self) -> Result<()> {
        self.emit(EV_SYN, SYN_REPORT, 0)
    }

    /// Press (value=1) or release (value=0) a single evdev key, with a SYN.
    pub fn key(&mut self, code: u16, press: bool) -> Result<()> {
        self.emit(EV_KEY, code, if press { 1 } else { 0 })?;
        self.syn()
    }

    /// Press a chord: hold `mods` (in order), tap `key`, release everything in
    /// reverse.
    ///
    /// CRITICAL: the modifier-down -> key-down -> key-up -> modifier-up events
    /// are emitted as one *contiguous* batch with **no inter-event sleep**. On
    /// KWin/Wayland a quiescent gap after a virtual modifier-down causes the
    /// compositor to drop the modifier before the key arrives, so an injected
    /// Ctrl+V degrades to a bare `v`.
    ///
    /// Every successful or attempted key-down is paired with a best-effort
    /// key-up, including when a later write fails. Physical modifiers are never
    /// "restored" through this virtual device: doing that leaves a virtual
    /// key-down with no future event that can release it.
    pub fn chord(&mut self, key: u16, mods: &[u16]) -> Result<()> {
        if let Some(code) = mods
            .iter()
            .find(|code| !keymap::EVDEV_MODIFIERS.contains(code))
        {
            return Err(format!("unsupported evdev modifier {code}"));
        }
        send_chord(key, mods, |code, press| self.key(code, press))
    }
}

impl Drop for UInput {
    fn drop(&mut self) {
        unsafe { libc::ioctl(self.file.as_raw_fd(), UI_DEV_DESTROY) };
    }
}

fn ioctl_set(fd: libc::c_int, req: libc::c_ulong, arg: libc::c_int) -> Result<()> {
    if unsafe { libc::ioctl(fd, req, arg) } < 0 {
        return Err(format!(
            "ioctl {req:#x}({arg}): {}",
            std::io::Error::last_os_error()
        ));
    }
    Ok(())
}

/// Send a complete chord transaction and clean up every key that may have gone
/// down. Cleanup continues after a release error so one failed write cannot
/// prevent the remaining modifiers from being released.
fn send_chord<F>(key: u16, mods: &[u16], mut emit: F) -> Result<()>
where
    F: FnMut(u16, bool) -> Result<()>,
{
    let mut pressed = Vec::with_capacity(mods.len() + 1);
    let mut first_error = None;

    for code in mods.iter().copied().chain(std::iter::once(key)) {
        // Track before writing: EV_KEY may have reached the kernel even if the
        // following SYN fails, so this key still needs a cleanup release.
        pressed.push(code);
        if let Err(error) = emit(code, true) {
            first_error = Some(error);
            break;
        }
    }

    if first_error.is_none() {
        match emit(key, false) {
            Ok(()) => {
                debug_assert_eq!(pressed.pop(), Some(key));
            }
            Err(error) => first_error = Some(error),
        }
    }

    for code in pressed.into_iter().rev() {
        if let Err(error) = emit(code, false) {
            if first_error.is_none() {
                first_error = Some(error);
            }
        }
    }

    match first_error {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::send_chord;

    #[test]
    fn successful_chord_releases_key_and_modifiers() {
        let mut events = Vec::new();
        send_chord(47, &[29, 42], |code, press| {
            events.push((code, press));
            Ok(())
        })
        .unwrap();

        assert_eq!(
            events,
            vec![
                (29, true),
                (42, true),
                (47, true),
                (47, false),
                (42, false),
                (29, false),
            ]
        );
    }

    #[test]
    fn key_down_failure_still_releases_every_possible_key() {
        let mut events = Vec::new();
        let mut call = 0;
        let result = send_chord(47, &[29, 42], |code, press| {
            call += 1;
            events.push((code, press));
            if call == 3 {
                Err("injected key-down failure".into())
            } else {
                Ok(())
            }
        });

        assert!(result.is_err());
        assert_eq!(
            events,
            vec![
                (29, true),
                (42, true),
                (47, true),
                (47, false),
                (42, false),
                (29, false),
            ]
        );
    }

    #[test]
    fn release_failure_does_not_skip_other_releases() {
        let mut events = Vec::new();
        let mut call = 0;
        let result = send_chord(47, &[29, 42], |code, press| {
            call += 1;
            events.push((code, press));
            if call == 5 {
                Err("injected modifier-up failure".into())
            } else {
                Ok(())
            }
        });

        assert!(result.is_err());
        assert_eq!(events.last(), Some(&(29, false)));
        assert_eq!(events.iter().filter(|(_, press)| !press).count(), 3);
    }
}
