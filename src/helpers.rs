use crate::state::now_epoch;

/// Format token count: 1000000 -> "1M", 200000 -> "200k"
pub fn fmt_tokens(t: u64) -> String {
    if t >= 1_000_000 {
        format!("{}M", t / 1_000_000)
    } else if t >= 1_000 {
        format!("{}k", t / 1_000)
    } else {
        format!("{t}")
    }
}

/// Format reset time as countdown: "2h30m", "45m", "now"
pub fn fmt_reset(reset_epoch: u64) -> String {
    let now = now_epoch();
    if reset_epoch <= now {
        return "now".to_string();
    }
    let diff = reset_epoch - now;
    let d = diff / 86400;
    let h = (diff % 86400) / 3600;
    let m = (diff % 3600) / 60;
    if d > 0 {
        format!("{d}d{h}h")
    } else if h > 0 {
        format!("{h}h{m}m")
    } else {
        format!("{m}m")
    }
}

/// Colour a remaining-% value: >50% white, 21-50% yellow, ≤20% red
pub fn colour_remain(remain: u32) -> String {
    if remain <= 20 {
        format!("\x1b[1;31m{remain}%\x1b[0m")
    } else if remain <= 50 {
        format!("\x1b[1;33m{remain}%\x1b[0m")
    } else {
        format!("\x1b[0;37m{remain}%\x1b[0m")
    }
}

/// ANSI hidden spacer: occupies 1 column but invisible
pub const HS: &str = "\x1b[8m.\x1b[0m";

// ANSI colour constants
pub const NC: &str = "\x1b[0m";
pub const DIM: &str = "\x1b[2m";
pub const ORANGE: &str = "\x1b[38;5;208m";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fmt_tokens() {
        assert_eq!(fmt_tokens(1_000_000), "1M");
        assert_eq!(fmt_tokens(200_000), "200k");
        assert_eq!(fmt_tokens(500), "500");
    }

    #[test]
    fn test_colour_remain_thresholds() {
        assert!(colour_remain(10).contains("1;31m")); // red
        assert!(colour_remain(20).contains("1;31m")); // red
        assert!(colour_remain(21).contains("1;33m")); // yellow
        assert!(colour_remain(50).contains("1;33m")); // yellow
        assert!(colour_remain(51).contains("0;37m")); // white
    }
}
