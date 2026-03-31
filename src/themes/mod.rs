pub mod pacman;
pub mod pikmin;

use crate::models::{Input, RawState};

pub trait Theme {
    fn render(&self, input: &Input, state: &RawState) -> String;
}
