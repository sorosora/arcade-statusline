use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ── Input from Claude Code (stdin JSON) ─────────────────────────────────────

#[derive(Debug, Deserialize, Default)]
pub struct Input {
    #[serde(default)]
    pub model: ModelField,
    #[serde(default)]
    pub version: Option<String>,
    #[serde(default)]
    pub context_window: ContextWindow,
    #[serde(default)]
    pub rate_limits: RateLimits,
}

#[derive(Debug, Deserialize, Default)]
#[serde(untagged)]
pub enum ModelField {
    Str(String),
    Obj {
        display_name: Option<String>,
        id: Option<String>,
    },
    #[default]
    None,
}

impl ModelField {
    pub fn display(&self) -> Option<String> {
        match self {
            Self::Str(s) if !s.is_empty() => Some(s.clone()),
            Self::Obj { display_name, id } => {
                let name = display_name.as_ref().or(id.as_ref())?;
                // Strip parenthesized suffixes like "(beta)"
                let cleaned = if let Some(idx) = name.find('(') {
                    name[..idx].trim().to_string()
                } else {
                    name.clone()
                };
                if cleaned.is_empty() { None } else { Some(cleaned) }
            }
            _ => None,
        }
    }
}

#[derive(Debug, Deserialize, Default)]
pub struct ContextWindow {
    #[serde(default)]
    pub used_percentage: f64,
    pub context_window_size: Option<u64>,
    pub total_tokens: Option<u64>,
}

impl ContextWindow {
    pub fn size(&self) -> Option<u64> {
        self.context_window_size.or(self.total_tokens)
    }

    pub fn used_int(&self) -> u32 {
        self.used_percentage.round() as u32
    }

    pub fn remain(&self) -> u32 {
        100u32.saturating_sub(self.used_int())
    }
}

#[derive(Debug, Deserialize, Default)]
pub struct RateLimits {
    pub five_hour: Option<RateLimit>,
    pub seven_day: Option<RateLimit>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct RateLimit {
    #[serde(default)]
    pub used_percentage: f64,
    pub resets_at: Option<u64>,
}

impl RateLimit {
    pub fn used_int(&self) -> u32 {
        self.used_percentage.round() as u32
    }

    pub fn remain(&self) -> u32 {
        100u32.saturating_sub(self.used_int())
    }

    pub fn is_hit(&self) -> bool {
        self.used_int() >= 100
    }
}

// ── Shared raw state (theme-independent) ────────────────────────────────────

#[derive(Debug, Serialize, Deserialize, Default)]
pub struct RawState {
    #[serde(default)]
    pub slots: HashMap<String, SlotRecord>,
    #[serde(default)]
    pub sessions: HashMap<String, u32>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct SlotRecord {
    pub consumed: bool,
}
