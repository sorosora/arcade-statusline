mod helpers;
mod models;
mod state;
mod themes;

use models::Input;
use std::io::Read;
use themes::Theme;

#[cfg(unix)]
fn parent_id() -> u32 {
    std::os::unix::process::parent_id()
}

#[cfg(windows)]
fn parent_id() -> u32 {
    std::process::id()
}

fn main() {
    // Parse arguments
    let args: Vec<String> = std::env::args().collect();
    let theme_name = args.iter()
        .position(|a| a == "--theme")
        .and_then(|i| args.get(i + 1))
        .map(|s| s.as_str())
        .unwrap_or("pacman");

    let demo_mode = args.iter()
        .position(|a| a == "--slot-offset")
        .and_then(|i| args.get(i + 1))
        .and_then(|s| s.parse::<i64>().ok());

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

    // Render with selected theme
    let output = match theme_name {
        "pikmin" => themes::pikmin::Pikmin.render(&input, &raw_state),
        "pacman" | _ => themes::pacman::Pacman.render(&input, &raw_state),
    };

    println!("{output}");
}
