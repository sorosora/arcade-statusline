use crate::models::{Input, RawState, SlotRecord};
use std::fs;
use std::time::{SystemTime, UNIX_EPOCH};

const STATE_PATH: &str = "/tmp/.claude-statusline-state.json";
const SLOT_MINUTES: u64 = 15;
const TRAIL_SLOTS: u64 = 36; // 9 hours

pub fn now_epoch() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

pub fn current_slot() -> u64 {
    now_epoch() / (SLOT_MINUTES * 60)
}

/// Position within 8-slot cycle: pos 0 = big flower slot
pub fn slot_pos(slot: u64) -> u8 {
    ((slot + 1) % 8) as u8
}

pub fn load() -> RawState {
    fs::read_to_string(STATE_PATH)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub fn save(state: &RawState) {
    if let Ok(json) = serde_json::to_string(state) {
        let _ = fs::write(STATE_PATH, json);
    }
}

/// Update shared state based on current input. Returns whether context was consumed this tick.
pub fn update(state: &mut RawState, input: &Input, session_id: &str) -> bool {
    let slot = current_slot();
    let slot_key = slot.to_string();
    let ctx_int = input.context_window.used_int();

    // Check if any rate limit is hit
    let rate_hit = input.rate_limits.five_hour.as_ref().is_some_and(|r| r.is_hit())
        || input.rate_limits.seven_day.as_ref().is_some_and(|r| r.is_hit());

    // Check if context was consumed since last update
    let consumed = if let Some(&last_ctx) = state.sessions.get(session_id) {
        ctx_int != last_ctx
    } else {
        ctx_int > 0
    };

    // Decide what to record for this slot
    if let Some(existing) = state.slots.get(&slot_key) {
        if existing.consumed {
            // Already recorded consumption — don't downgrade
            state.sessions.remove(session_id);
        } else if !rate_hit && consumed {
            // Upgrade: was not consumed, now consumed
            state.slots.insert(slot_key, SlotRecord { consumed: true });
            state.sessions.remove(session_id);
        } else {
            state.sessions.insert(session_id.to_string(), ctx_int);
        }
    } else if rate_hit {
        state.slots.insert(slot_key, SlotRecord { consumed: false });
        state.sessions.insert(session_id.to_string(), ctx_int);
    } else if consumed {
        state.slots.insert(slot_key, SlotRecord { consumed: true });
        state.sessions.remove(session_id);
    } else {
        state.slots.insert(slot_key, SlotRecord { consumed: false });
        state.sessions.insert(session_id.to_string(), ctx_int);
    }

    // Prune old slots
    let oldest = slot.saturating_sub(TRAIL_SLOTS);
    state.slots.retain(|k, _| {
        k.parse::<u64>().map_or(false, |s| s >= oldest)
    });

    consumed
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::*;

    fn make_input(ctx_pct: f64) -> Input {
        Input {
            context_window: ContextWindow {
                used_percentage: ctx_pct,
                ..Default::default()
            },
            ..Default::default()
        }
    }

    #[test]
    fn test_slot_pos() {
        // pos 0 = big flower slot
        // Find a slot where (slot + 1) % 8 == 0
        assert_eq!(slot_pos(7), 0);
        assert_eq!(slot_pos(15), 0);
        assert_eq!(slot_pos(8), 1);
        assert_eq!(slot_pos(14), 7);
    }

    #[test]
    fn test_first_update_with_context_records_consumed() {
        let mut state = RawState::default();
        let input = make_input(5.0);
        let consumed = update(&mut state, &input, "test-session");

        assert!(consumed);
        let slot_key = current_slot().to_string();
        assert!(state.slots[&slot_key].consumed);
    }

    #[test]
    fn test_first_update_zero_context_not_consumed() {
        let mut state = RawState::default();
        let input = make_input(0.0);
        let consumed = update(&mut state, &input, "test-session");

        assert!(!consumed);
        let slot_key = current_slot().to_string();
        assert!(!state.slots[&slot_key].consumed);
    }

    #[test]
    fn test_no_downgrade_consumed_slot() {
        let mut state = RawState::default();
        let slot_key = current_slot().to_string();

        // First: consume
        state.slots.insert(slot_key.clone(), SlotRecord { consumed: true });

        // Second: same context % (no consumption)
        let input = make_input(5.0);
        state.sessions.insert("s1".to_string(), 5);
        update(&mut state, &input, "s1");

        // Should still be consumed
        assert!(state.slots[&slot_key].consumed);
    }

    #[test]
    fn test_upgrade_unconsumed_to_consumed() {
        let mut state = RawState::default();
        let slot_key = current_slot().to_string();

        // Start with not consumed
        state.slots.insert(slot_key.clone(), SlotRecord { consumed: false });
        state.sessions.insert("s1".to_string(), 5);

        // Now context changed
        let input = make_input(10.0);
        update(&mut state, &input, "s1");

        assert!(state.slots[&slot_key].consumed);
    }

    #[test]
    fn test_rate_limit_blocks_planting() {
        let mut state = RawState::default();
        let input = Input {
            context_window: ContextWindow {
                used_percentage: 5.0,
                ..Default::default()
            },
            rate_limits: RateLimits {
                five_hour: Some(RateLimit {
                    used_percentage: 100.0,
                    resets_at: None,
                }),
                seven_day: None,
            },
            ..Default::default()
        };

        let consumed = update(&mut state, &input, "s1");
        // Context did change (first session with ctx > 0), so consumed is true
        // But the slot should record consumed: false because rate limit blocked planting
        assert!(consumed);
        let slot_key = current_slot().to_string();
        assert!(!state.slots[&slot_key].consumed);
    }

    #[test]
    fn test_prune_old_slots() {
        let mut state = RawState::default();
        let slot = current_slot();

        // Insert an old slot (way beyond trail)
        let old_key = (slot - 100).to_string();
        state.slots.insert(old_key.clone(), SlotRecord { consumed: true });

        let input = make_input(0.0);
        update(&mut state, &input, "s1");

        assert!(!state.slots.contains_key(&old_key));
    }
}
