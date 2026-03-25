# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repo contains a Pac-Man inspired statusline script (`statusline.sh`) and installer (`install.sh`) for Claude Code.

## statusline.sh Architecture

Bash script that reads JSON from stdin and renders a single-line chase game with ANSI colors.

Core flow:
1. Parse JSON with `jq` -- extract model, version, context window usage, 5h/7d rate limit percentages and reset times
2. Pac-Man (ᗧ/●) position based on context usage, minimum start position 12 to leave chase room for ghosts
3. Red ghost (ᗩ/ᗣ) = 5h rate limit, purple ghost = 7d rate limit
4. 7d ghost caged in left-side room (3 cells + ▌ door) when usage < 50%, bounces left/right each update
5. Ghosts move proportionally between their start position and Pac-Man (relative distance)
6. Animation toggles each update: Pac-Man mouth open/close, two ghosts alternate legs (ᗩ ↔ ᗣ, opposite phase)
7. Red cherry (ᐝ) at 95% position marks auto-compact threshold
8. Rate limit 100% → ghost catches Pac-Man → GAME OVER
9. Neon blue (38;5;27) rounded double-line border with 1-cell padding
10. Header: CLAUDE (orange) + version (dim) left, model (white) + context size + remaining % right
11. Footer: rate limit info, % shows remaining amount, ↓ marks reset time

## Conventions

- Commit messages must not mention AI or related tools as author
- Use "Pac-Man inspired" rather than "Pac-Man" as the product name (trademark)
