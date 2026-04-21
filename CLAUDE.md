# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repo contains an arcade-themed statusline for Claude Code, implemented as a Rust binary (`src/`) with two themes: Pac-Man and Pikmin Bloom. Legacy shell/PowerShell scripts (`statusline.sh`, `statusline.ps1`) are deprecated.

## Rust Architecture

`src/main.rs` reads JSON from stdin, updates shared state, and delegates rendering to the selected theme.

- `src/models.rs` -- Input JSON deserialization (model, context window, rate limits) and shared state types
- `src/helpers.rs` -- Formatting utilities (tokens, reset time, color coding) and ANSI constants
- `src/settings.rs` -- Reads user settings from `~/.claude/settings.json` (e.g., `effortLevel`)
- `src/state.rs` -- Persistent state management (`/tmp/.claude-statusline-state.json`), 15-min slot tracking, session-based context consumption detection using parent PID
- `src/themes/pacman.rs` -- Pac-Man chase game theme
- `src/themes/pikmin.rs` -- Pikmin Bloom flower planting theme

### Pac-Man Theme

Single-line chase game with ANSI colors:
1. Pac-Man (ᗧ/●) position based on context usage, minimum start position 12
2. Red ghost (ᗩ/ᗣ) = 5h rate limit, purple ghost = 7d rate limit
3. 7d ghost caged in left-side room when usage < 50%, bounces left/right each update
4. Ghosts move proportionally between start position and Pac-Man
5. Animation toggles each update: mouth open/close, ghosts alternate legs in opposite phase
6. Red cherry (ᐝ) at 95% position marks auto-compact threshold
7. Rate limit 100% → GAME OVER
8. Neon blue (38;5;27) rounded double-line border with 1-cell padding
9. `effortLevel` from `~/.claude/settings.json` appears in the footer after the 5h rate limit; hidden during GAME OVER

### Pikmin Bloom Theme

Flower planting trail with 15-minute time slots:
1. Trail (past 9h) + Pikmin squad + Future (1h ahead)
2. Context consumed → plant flower; idle → dot (·) or seedling (🌱)
3. Big flower cycle every 8 slots (~2h)
4. Rate limit reset times shown as fruit in future slots
5. Rate limit hit blocks flower planting
6. Sky and grass decorative rows
7. `effortLevel` from `~/.claude/settings.json` appears in the footer before the bloom indicator; `xhigh` / `max` add ⏩; hidden when a rate limit is hit

## Conventions

- Commit messages must not mention AI or related tools as author
- Use "Pac-Man inspired" rather than "Pac-Man" as the product name (trademark)
- Shell/PowerShell scripts are deprecated; new features go in Rust only
