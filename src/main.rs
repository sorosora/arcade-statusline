mod helpers;
mod models;
mod state;
mod themes;

use models::Input;
use std::io::Read;
use themes::Theme;

fn main() {
    // Parse --theme argument
    let args: Vec<String> = std::env::args().collect();
    let theme_name = args.iter()
        .position(|a| a == "--theme")
        .and_then(|i| args.get(i + 1))
        .map(|s| s.as_str())
        .unwrap_or("pacman");

    // Read JSON from stdin
    let mut input_str = String::new();
    std::io::stdin().read_to_string(&mut input_str).unwrap_or_default();

    let input: Input = serde_json::from_str(&input_str).unwrap_or_default();

    // Load and update shared state
    let session_id = std::process::id().to_string();
    let mut raw_state = state::load();
    state::update(&mut raw_state, &input, &session_id);
    state::save(&raw_state);

    // Render with selected theme
    let output = match theme_name {
        "pikmin" => themes::pikmin::Pikmin.render(&input, &raw_state),
        "pacman" | _ => themes::pacman::Pacman.render(&input, &raw_state),
    };

    println!("{output}");
}
