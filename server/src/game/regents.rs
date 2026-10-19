//! REGENT'S RULE (docs/regents_rule/RULE_DESIGN.md), the server's half. Nothing yet: the skilling
//! loop starts on the client, where the woodcutting minigame is played and tuned before the server
//! replays it (a challenge kind of this genre's, resolved by `resolve_challenge`).

use crate::genre::regents as rules;

pub struct Regents;
pub static REGENTS: Regents = Regents;

impl crate::game::Genre for Regents {
    fn claims(&self) -> &'static crate::genre::Claims {
        &rules::CLAIMS
    }
}
