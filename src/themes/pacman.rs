use crate::helpers::*;
use crate::models::{Input, RawState};
use crate::themes::Theme;

// Original bash layout: MAP_W=50 inner + 2 border + 2 padding = TOTAL_W=54
const MAP_W: usize = 50;
const PAD: usize = 1;
const TOTAL_W: usize = MAP_W + 2 + PAD * 2; // 54

const PAC_MIN: usize = 12;

const ANIM_PATH: &str = "/tmp/.claude-pacman-chomp";

// Colours
const BLUE: &str = "\x1b[38;5;27m";
const RED: &str = "\x1b[1;31m";
const PURPLE: &str = "\x1b[1;35m";
const YELLOW: &str = "\x1b[1;33m";
const WHITE: &str = "\x1b[0;37m";

/// Toggle chomp state, return (pac_char, g1_char, g2_char)
fn animation() -> (&'static str, &'static str, &'static str) {
    let current = std::fs::read_to_string(ANIM_PATH)
        .unwrap_or_default()
        .trim()
        .to_string();
    if current == "1" {
        let _ = std::fs::write(ANIM_PATH, "0");
        // mouth closed, ghost legs swap
        ("●", "ᗩ", "ᗣ")
    } else {
        let _ = std::fs::write(ANIM_PATH, "1");
        // mouth open, ghost legs: ᗣ / ᗩ
        ("ᗧ", "ᗣ", "ᗩ")
    }
}

/// Repeat horizontal line character
fn rep_hline(n: usize) -> String {
    (0..n).map(|_| format!("{BLUE}═{NC}")).collect()
}

pub struct Pacman;

impl Theme for Pacman {
    fn render(&self, input: &Input, _state: &RawState) -> String {
        let ctx_int = input.context_window.used_int() as usize;
        let ctx_remain = input.context_window.remain();
        let five = &input.rate_limits.five_hour;
        let week = &input.rate_limits.seven_day;

        let five_int = five.as_ref().map(|r| r.used_int() as usize).unwrap_or(0);
        let week_int = week.as_ref().map(|r| r.used_int() as usize).unwrap_or(0);
        let five_remain = five.as_ref().map(|r| r.remain()).unwrap_or(100);
        let week_remain = week.as_ref().map(|r| r.remain()).unwrap_or(100);

        let (pac_char, g1_char, g2_char) = animation();

        // ── Positions ───────────────────────────────────────────────
        let mut pac_pos = PAC_MIN + ctx_int * (MAP_W - 1 - PAC_MIN) / 100;
        if pac_pos < PAC_MIN { pac_pos = PAC_MIN; }
        if pac_pos >= MAP_W { pac_pos = MAP_W - 1; }

        let mut g1: i32 = -1;
        let mut g2: i32 = -1;
        let mut game_over = false;
        let mut g2_caged = false;

        // 5h ghost (red, g1)
        if five.is_some() {
            if five_int >= 100 {
                g1 = pac_pos as i32;
                game_over = true;
            }
            // g1_pending handled below after ROOM_W
        }

        // 7d ghost (purple, g2) — caged when remaining > 50%
        if week.is_some() {
            if week_remain > 50 {
                g2_caged = true;
            }
            if !g2_caged && week_int >= 100 {
                g2 = pac_pos as i32;
                game_over = true;
            }
        }

        // Room offset
        let room_w: usize = if g2_caged { 5 } else { 0 }; // 3 interior + 1 wall + 1 gap
        if g2_caged && pac_pos < room_w {
            pac_pos = room_w;
        }

        // Resolve pending ghost positions
        if five.is_some() && five_int < 100 {
            let g1_start = room_w;
            g1 = (g1_start + five_int * pac_pos.saturating_sub(g1_start) / 100) as i32;
        }
        if week.is_some() && !g2_caged && week_int < 100 {
            g2 = (week_int * pac_pos / 100) as i32;
        }

        // Resolve overlaps
        if !game_over {
            if g1 >= 0 && g1 as usize >= pac_pos && pac_pos > 0 { g1 = pac_pos as i32 - 1; }
            if g2 >= 0 && g2 as usize >= pac_pos && pac_pos > 0 { g2 = pac_pos as i32 - 1; }
        }
        if g1 >= 0 && g2 >= 0 && g1 == g2 {
            if five_int <= week_int { if g1 > 0 { g1 -= 1; } }
            else if g2 > 0 { g2 -= 1; }
        }
        if !game_over {
            if g1 >= 0 && g1 as usize == pac_pos && pac_pos > 0 { g1 = pac_pos as i32 - 1; }
            if g2 >= 0 && g2 as usize == pac_pos && pac_pos > 0 { g2 = pac_pos as i32 - 1; }
        }

        // GAME OVER removed from game line — shown in footer instead

        // Cherry at 95% context
        let cherry_pos = PAC_MIN + 95 * (MAP_W - 1 - PAC_MIN) / 100;

        // ── Build game line ─────────────────────────────────────────
        let mut game = String::new();

        // Caged ghost room (3 interior + wall + gap)
        if g2_caged {
            if pac_char == "ᗧ" {
                // Ghost on left side of room
                game += &format!("{PURPLE}{g2_char}{NC}  {BLUE}▌{NC} ");
            } else {
                // Ghost on right side of room
                game += &format!("  {PURPLE}{g2_char}{NC}{BLUE}▌{NC} ");
            }
        }

        for i in room_w..MAP_W {
            if game_over && i == pac_pos {
                // Ghost caught pac-man
                if g1 >= 0 && g1 as usize == pac_pos {
                    game += &format!("{RED}{g1_char}{NC}");
                } else {
                    game += &format!("{PURPLE}{g2_char}{NC}");
                }
            } else if !game_over && i == pac_pos {
                game += &format!("{YELLOW}{pac_char}{NC}");
            } else if g1 >= 0 && i == g1 as usize && !(game_over && g1 as usize == pac_pos) {
                game += &format!("{RED}{g1_char}{NC}");
            } else if g2 >= 0 && i == g2 as usize && !(game_over && g2 as usize == pac_pos) {
                game += &format!("{PURPLE}{g2_char}{NC}");
            } else if i > pac_pos && i == cherry_pos {
                game += &format!("{RED}ᐝ{NC}");
            } else if i > pac_pos {
                game += &format!("{WHITE}·{NC}");
            } else {
                game.push(' ');
            }
        }

        // ── Border ──────────────────────────────────────────────────
        let hline_w = MAP_W + PAD * 2;
        let top_border = format!("{BLUE}╭{NC}{}{BLUE}╮{NC}", rep_hline(hline_w));
        let bot_border = format!("{BLUE}╰{NC}{}{BLUE}╯{NC}", rep_hline(hline_w));
        let game_line = format!("{BLUE}║{NC} {game} {BLUE}║{NC}");

        // ── Header ──────────────────────────────────────────────────
        let ctx_size = input.context_window.size().map(fmt_tokens).unwrap_or_default();
        let model_str = input.model.display().unwrap_or_default();

        let mut left_plain = "CLAUDE".to_string();
        if let Some(v) = &input.version {
            left_plain += &format!(" v{v}");
        }
        let left_len = left_plain.len();

        // Right: "model size Xontext XX% left" (ᗧ replaces X visually)
        let mut right_plain = String::new();
        if !model_str.is_empty() { right_plain += &format!("{model_str} "); }
        if !ctx_size.is_empty() { right_plain += &format!("{ctx_size} "); }
        right_plain += &format!("Xontext {ctx_remain}% left");
        let right_len = right_plain.len();

        let gap = TOTAL_W.saturating_sub(left_len + right_len).max(2);
        let gap_pad = " ".repeat(gap);

        let mut left_colored = format!("{ORANGE}CLAUDE{NC}");
        if let Some(v) = &input.version {
            left_colored += &format!(" {DIM}v{v}{NC}");
        }

        let mut right_colored = String::new();
        if !model_str.is_empty() { right_colored += &format!("{WHITE}{model_str}{NC} "); }
        if !ctx_size.is_empty() { right_colored += &format!("{DIM}{ctx_size}{NC} "); }
        let ctx_c = colour_remain(ctx_remain);
        right_colored += &format!("{YELLOW}ᗧ{NC}{DIM}ontext{NC} {ctx_c} {DIM}left{NC}");

        let header = format!("{left_colored}{gap_pad}{right_colored}");

        // ── Footer ──────────────────────────────────────────────────
        let mut footer = String::new();

        if week.is_some() || five.is_some() {
            let mut limit_line = String::new();

            if let Some(w) = week {
                let w_c = colour_remain(week_remain);
                limit_line += &format!("{PURPLE}ᗩ{NC} {DIM}7d{NC} {w_c}");
                if let Some(reset) = w.resets_at {
                    let rs = fmt_reset(reset);
                    limit_line += &format!(" {DIM}↓{rs}{NC}");
                }
            }

            if let Some(f) = five {
                if !limit_line.is_empty() { limit_line += "  "; }
                let f_c = colour_remain(five_remain);
                limit_line += &format!("{RED}ᗩ{NC} {DIM}5h{NC} {f_c}");
                if let Some(reset) = f.resets_at {
                    let rs = fmt_reset(reset);
                    limit_line += &format!(" {DIM}↓{rs}{NC}");
                }
            }

            if game_over {
                let go_text = format!("{RED}GAME OVER{NC}");
                let go_plain_len = 9; // "GAME OVER"
                // Estimate visible length by counting non-escape chars
                let mut vis_len = 0usize;
                let mut in_esc = false;
                for c in limit_line.chars() {
                    if c == '\x1b' { in_esc = true; }
                    else if in_esc { if c.is_ascii_alphabetic() { in_esc = false; } }
                    else { vis_len += 1; }
                }
                let go_gap = TOTAL_W.saturating_sub(vis_len + go_plain_len).max(2);
                limit_line += &" ".repeat(go_gap);
                limit_line += &go_text;
            }
            footer = format!("\n{limit_line}");
        }

        // ── Combine ─────────────────────────────────────────────────
        format!("{header}\n{top_border}\n{game_line}\n{bot_border}{footer}")
    }
}
