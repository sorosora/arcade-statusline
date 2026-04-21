use std::path::PathBuf;

fn settings_path() -> Option<PathBuf> {
    let home = std::env::var("HOME")
        .ok()
        .or_else(|| std::env::var("USERPROFILE").ok())?;
    Some(PathBuf::from(home).join(".claude").join("settings.json"))
}

/// Read `effortLevel` from `~/.claude/settings.json`. Returns `None` if the
/// file is missing, unreadable, not JSON, or the field is absent/non-string.
pub fn read_effort_level() -> Option<String> {
    let path = settings_path()?;
    let content = std::fs::read_to_string(&path).ok()?;
    let v: serde_json::Value = serde_json::from_str(&content).ok()?;
    v.get("effortLevel")?.as_str().map(String::from)
}
