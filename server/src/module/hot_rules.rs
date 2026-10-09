//! THE HOT RULES, LIVE (CONTENT_TOOLING_SPEC §4, DECISIONS #201). Every rule this build declares
//! (`crate::hot::ALL`, baked from the rule sets) has a row in `hot_rule` holding the value the game
//! runs on NOW. Reducers read it (`hot_number`), every client subscribes to it (the foundation
//! does, not a game's config), and an admin changes it while the game runs (`set_rule`).
//!
//! THE TABLE NEVER CHANGES SHAPE (old clients read it: docs/rules/compatibility.md). `text` and
//! `overridden` are there from the start so no rule kind needs a new column.
//!
//! Keeping it current: `sync_hot_rules` runs at init and on every connect. A rule nobody changed
//! follows this build's default, so a republish with a new default takes effect without a wipe; a
//! rule an admin set keeps its value (unless the new bounds no longer allow it); a rule this build
//! no longer has is removed.

use super::*;

#[table(accessor = hot_rule, public)]
pub struct HotRuleRow {
    /// `<owner>.<name>`, like `foundation.interact_range_m`.
    #[primary_key]
    pub key: String,
    /// The value, for a number, a whole number or a flag (0/1).
    pub number: f64,
    /// The value, for words.
    pub text: String,
    /// An admin set it (`set_rule`): it keeps its value across republishes until `reset_rule`.
    pub overridden: bool,
    pub updated_at: Timestamp,
}

/// The longest words a TEXT rule may hold.
pub const HOT_TEXT_MAX: usize = 512;

/// Bring `hot_rule` in line with this build's rules (see the file's head).
pub fn sync_hot_rules(ctx: &ReducerContext) {
    for r in crate::hot::ALL {
        match ctx.db.hot_rule().key().find(r.key.to_string()) {
            None => {
                ctx.db.hot_rule().insert(HotRuleRow {
                    key: r.key.to_string(),
                    number: r.number,
                    text: r.text.to_string(),
                    overridden: false,
                    updated_at: ctx.timestamp,
                });
            }
            Some(row) => {
                let stale = !row.overridden && (row.number != r.number || row.text != r.text);
                let out_of_bounds = row.overridden && r.check(row.number).is_err();
                if stale || out_of_bounds {
                    if out_of_bounds {
                        log::warn!("hot rule {}: the admin's {} is outside the new bounds; back to {}", r.key, row.number, r.number);
                    }
                    ctx.db.hot_rule().key().update(HotRuleRow {
                        number: r.number,
                        text: r.text.to_string(),
                        overridden: false,
                        updated_at: ctx.timestamp,
                        ..row
                    });
                }
            }
        }
    }
    let gone: Vec<String> = ctx.db.hot_rule().iter().map(|row| row.key).filter(|k| crate::hot::find(k).is_none()).collect();
    for k in gone {
        ctx.db.hot_rule().key().delete(k);
    }
}

/// A rule's value now: the table's, or this build's default when the row is not there yet.
pub fn hot_number(ctx: &ReducerContext, r: &crate::hot::Rule) -> f64 {
    ctx.db.hot_rule().key().find(r.key.to_string()).map(|row| row.number).unwrap_or(r.number)
}

/// A flag rule's value now.
pub fn hot_flag(ctx: &ReducerContext, r: &crate::hot::Rule) -> bool {
    hot_number(ctx, r) != 0.0
}

/// A words rule's value now.
pub fn hot_text(ctx: &ReducerContext, r: &crate::hot::Rule) -> String {
    ctx.db.hot_rule().key().find(r.key.to_string()).map(|row| row.text).unwrap_or_else(|| r.text.to_string())
}

/// ADMIN: change a rule while the game runs. Within the rule's bounds; it keeps the value across
/// republishes until `reset_rule`. `text` is read for a TEXT rule, `number` for the rest.
#[reducer]
pub fn set_rule(ctx: &ReducerContext, key: String, number: f64, text: String) -> Result<(), String> {
    require_admin(ctx)?;
    let r = crate::hot::find(&key).ok_or_else(|| format!("no hot rule '{key}'"))?;
    r.check(number)?;
    if text.len() > HOT_TEXT_MAX {
        return Err(format!("{key}: at most {HOT_TEXT_MAX} bytes of text"));
    }
    let (number, text) = if r.kind == crate::hot::Kind::Text { (r.number, text) } else { (number, r.text.to_string()) };
    let row = HotRuleRow { key: key.clone(), number, text, overridden: true, updated_at: ctx.timestamp };
    if ctx.db.hot_rule().key().find(key).is_some() {
        ctx.db.hot_rule().key().update(row);
    } else {
        ctx.db.hot_rule().insert(row);
    }
    Ok(())
}

/// ADMIN: put a rule back to this build's default (it follows republishes again).
#[reducer]
pub fn reset_rule(ctx: &ReducerContext, key: String) -> Result<(), String> {
    require_admin(ctx)?;
    let r = crate::hot::find(&key).ok_or_else(|| format!("no hot rule '{key}'"))?;
    let row = HotRuleRow { key: key.clone(), number: r.number, text: r.text.to_string(), overridden: false, updated_at: ctx.timestamp };
    if ctx.db.hot_rule().key().find(key).is_some() {
        ctx.db.hot_rule().key().update(row);
    } else {
        ctx.db.hot_rule().insert(row);
    }
    Ok(())
}
