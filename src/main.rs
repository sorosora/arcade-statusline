mod helpers;
mod models;
mod settings;
mod state;
mod themes;

use models::Input;
use std::io::Read;
use themes::Theme;

const BUDDY_RESERVE: usize = 20; // sprite (~14) + padding; speech bubble is transient

#[cfg(unix)]
fn parent_id() -> u32 {
    std::os::unix::process::parent_id()
}

#[cfg(windows)]
fn parent_id() -> u32 {
    std::process::id()
}

/// Detect terminal width via /dev/tty (bypasses stdin/stdout/stderr redirection)
#[cfg(unix)]
fn terminal_cols() -> usize {
    use std::os::unix::io::AsRawFd;

    #[repr(C)]
    struct Winsize {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    }
    unsafe extern "C" {
        fn ioctl(
            fd: std::os::raw::c_int,
            request: std::os::raw::c_ulong,
            ...
        ) -> std::os::raw::c_int;
    }
    #[cfg(target_os = "macos")]
    const TIOCGWINSZ: std::os::raw::c_ulong = 0x40087468;
    #[cfg(not(target_os = "macos"))]
    const TIOCGWINSZ: std::os::raw::c_ulong = 0x5413;

    // Open /dev/tty — the controlling terminal, regardless of redirection
    if let Ok(tty) = std::fs::File::open("/dev/tty") {
        let fd = tty.as_raw_fd();
        unsafe {
            let mut ws = std::mem::zeroed::<Winsize>();
            if ioctl(fd, TIOCGWINSZ, &mut ws as *mut Winsize) == 0 && ws.ws_col > 0 {
                return ws.ws_col as usize;
            }
        }
    }
    120
}

#[cfg(windows)]
fn terminal_cols() -> usize {
    120
}

fn print_help() {
    eprintln!("arcade-statusline — Arcade-themed statusline for Claude Code");
    eprintln!();
    eprintln!("Usage: arcade-statusline [OPTIONS]");
    eprintln!();
    eprintln!("Options:");
    eprintln!("  --theme <NAME>       Theme: pacman (default), pikmin");
    eprintln!("  --width <N>          Override statusline width (auto-detected)");
    eprintln!("  --narrow-emoji       Force narrow emoji mode (auto-detected for JetBrains)");
    eprintln!("  --buddy-padding      Add padding lines around statusline for Claude Code");
    eprintln!("                       buddy companion alignment in narrow-emoji terminals.");
    eprintln!("                       Adds 1 line above and 5 lines below the statusline");
    eprintln!("                       so the buddy sprite doesn't overlap with content.");
    eprintln!("  --slot-offset <N>    Shift time slots by N (demo/debug)");
    eprintln!("  --help               Show this help");
    eprintln!();
    eprintln!("Example (settings.json):");
    eprintln!(r#"  "statusLine": {{"#);
    eprintln!(r#"    "type": "command","#);
    eprintln!(r#"    "command": "arcade-statusline --theme pikmin --buddy-padding""#);
    eprintln!(r#"  }}"#);
}

fn main() {
    // Parse arguments
    let args: Vec<String> = std::env::args().collect();

    if args.iter().any(|a| a == "--help" || a == "-h") {
        print_help();
        return;
    }

    let theme_name = args.iter()
        .position(|a| a == "--theme")
        .and_then(|i| args.get(i + 1))
        .map(|s| s.as_str())
        .unwrap_or("pacman");

    let demo_mode = args.iter()
        .position(|a| a == "--slot-offset")
        .and_then(|i| args.get(i + 1))
        .and_then(|s| s.parse::<i64>().ok());

    let manual_width = args.iter()
        .position(|a| a == "--width")
        .and_then(|i| args.get(i + 1))
        .and_then(|s| s.parse::<usize>().ok());

    // Detect narrow-emoji terminals (JetBrains JediTerm renders emoji as 1 col instead of 2)
    let narrow_emoji = args.iter().any(|a| a == "--narrow-emoji")
        || std::env::var("TERMINAL_EMULATOR")
            .is_ok_and(|v| v.contains("JetBrains"));

    let buddy_padding = args.iter().any(|a| a == "--buddy-padding") && narrow_emoji;

    if let Some(offset) = demo_mode {
        state::set_slot_offset(offset);
    }

    // Read JSON from stdin
    let mut input_str = String::new();
    std::io::stdin().read_to_string(&mut input_str).unwrap_or_default();

    let input: Input = serde_json::from_str(&input_str).unwrap_or_default();

    let mut raw_state = state::load();

    if demo_mode.is_none() {
        // Normal mode: update and persist state
        let session_id = parent_id().to_string();
        state::update(&mut raw_state, &input, &session_id);
        state::save(&raw_state);
    }
    // Demo mode: read-only, don't modify state

    // Calculate available width for statusline (reserve space for buddy companion)
    let max_width = manual_width.unwrap_or_else(|| {
        terminal_cols().saturating_sub(BUDDY_RESERVE)
    });

    // Render with selected theme
    let output = match theme_name {
        "pikmin" => themes::pikmin::Pikmin { narrow_emoji, buddy_padding }.render(&input, &raw_state, max_width),
        "pacman" | _ => themes::pacman::Pacman.render(&input, &raw_state, max_width),
    };

    println!("{output}");
}
