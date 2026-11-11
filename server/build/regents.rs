// THE REGENTS GENRE'S BUILD STEP: its baked content (shared/content/regents/{item,skill,node,recipe,station}
// .json, made by tools/bake_content.gd from game/regents/content/) -> $OUT_DIR/regents_data.rs, included
// by `genre::regents`. Checked here so a content mistake fails the BUILD: a node giving an item that does
// not exist, a recipe at a station nobody built, a round that cannot be played, a tool with no tier.

use std::{env, fs, path::PathBuf};

fn baked(name: &str) -> Vec<serde_json::Value> {
    let path = PathBuf::from(format!("../shared/content/regents/{name}.json"));
    println!("cargo:rerun-if-changed={}", path.display());
    let Ok(text) = fs::read_to_string(&path) else { return Vec::new() };
    let v: serde_json::Value = serde_json::from_str(&text).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    v["items"].as_array().cloned().unwrap_or_default()
}

fn int(o: &serde_json::Value, k: &str, what: &str) -> i64 {
    o.get(k).and_then(|x| x.as_i64()).unwrap_or_else(|| panic!("regents content: {what} has no whole number '{k}'"))
}

fn text(o: &serde_json::Value, k: &str, what: &str) -> String {
    o.get(k).and_then(|x| x.as_str()).unwrap_or_else(|| panic!("regents content: {what} has no text '{k}'")).to_string()
}

/// A round's params as Rust, checked: `Minigame::None` for none.
fn minigame(m: &serde_json::Value, what: &str) -> String {
    let Some(kind) = m.get("kind").and_then(|k| k.as_str()) else { return "Minigame::None".into() };
    let f = |k: &str| int(m, k, what);
    match kind {
        "chop" => {
            assert!(f("swing_ms") > 0 && f("target_chops") > 0 && f("target_chops") <= f("duration_ms") / f("swing_ms") + 1,
                "regents content: {what}'s branch dodge cannot be played");
            // Knots (2026-11-07): absent in a bake from before them, so 0 (none).
            let opt = |k: &str| m.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
            format!("Minigame::Chop(chop::ChopParams {{ duration_ms: {}, swing_ms: {}, stagger_ms: {}, branch_permille: {}, safe_segments: {}, target_chops: {}, knot_permille: {}, knot_beat_ms: {} }})",
                f("duration_ms"), f("swing_ms"), f("stagger_ms"), f("branch_permille"), f("safe_segments"), f("target_chops"), opt("knot_permille"), opt("knot_beat_ms"))
        }
        "crack" => {
            assert!(f("swing_ms") > 0 && f("notches") >= 2 && f("target_hits") > 0 && f("margin_pm") <= 500,
                "regents content: {what}'s crack the rock cannot be played");
            // Brittle notches (2026-11-07): absent in a bake from before them, so 0 (none).
            let opt = |k: &str| m.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
            format!("Minigame::Crack(crack::CrackParams {{ duration_ms: {}, swing_ms: {}, stagger_ms: {}, split_ms: {}, notches: {}, bend_pm: {}, radius_pm: {}, margin_pm: {}, target_hits: {}, brittle_permille: {}, ring_ms: {} }})",
                f("duration_ms"), f("swing_ms"), f("stagger_ms"), f("split_ms"), f("notches"), f("bend_pm"), f("radius_pm"), f("margin_pm"), f("target_hits"),
                opt("brittle_permille"), opt("ring_ms"))
        }
        "smelt" => {
            assert!(f("pour_tolerance") > 0 && f("band_period_ticks") > 0 && f("target_hi") >= f("target_lo"), "regents content: {what}'s smelt cannot be played");
            format!("Minigame::Smelt(smelt::SmeltParams {{ heat_ms: {}, pour_ms: {}, pour_ready_ms: {}, pump_ms: {}, pump_heat: {}, cool_per_tick: {}, start_heat: {}, band_center: {}, band_amp: {}, band_period_ticks: {}, band_half_start: {}, band_half_end: {}, burn_line: {}, pour_rate: {}, target_lo: {}, target_hi: {}, pour_tolerance: {}, heat_weight_pct: {} }})",
                f("heat_ms"), f("pour_ms"), f("pour_ready_ms"), f("pump_ms"), f("pump_heat"), f("cool_per_tick"), f("start_heat"), f("band_center"), f("band_amp"),
                f("band_period_ticks"), f("band_half_start"), f("band_half_end"), f("burn_line"), f("pour_rate"), f("target_lo"), f("target_hi"),
                f("pour_tolerance"), f("heat_weight_pct"))
        }
        "beat" => {
            // Smelting as a rhythm track (Luke, 2026-11-07): two notes' windows never meet (a note is at least half a
            // beat from the next), the windows nest, and the mold's line can be reached.
            assert!(f("beat_ms") > 0 && f("beat_ms") % 2 == 0 && f("good_ms") * 4 <= f("beat_ms") && f("perfect_ms") > 0 && f("perfect_ms") <= f("good_ms")
                && f("beats") >= 1 && f("lead_beats") >= 0 && f("hold_beats") >= 0 && f("pour_tolerance") > 0 && f("target_hi") >= f("target_lo")
                && f("pour_ms") >= 0 && f("pour_ms") % 50 == 0 && (0..=100).contains(&f("track_weight_pct")),
                "regents content: {what}'s rhythm smelt cannot be played (a beat even and at least four times the outer window, the inner window inside it, the pour in 50 ms steps)");
            format!("Minigame::Beat(beat::BeatParams {{ beat_ms: {}, lead_beats: {}, beats: {}, rest_pm: {}, offbeat_pm: {}, hold_pm: {}, hold_beats: {}, perfect_ms: {}, good_ms: {}, good_pm: {}, stray_pm: {}, pour_ms: {}, pour_ready_ms: {}, pour_rate: {}, target_lo: {}, target_hi: {}, pour_tolerance: {}, track_weight_pct: {}, slag_pm: {} }})",
                f("beat_ms"), f("lead_beats"), f("beats"), f("rest_pm"), f("offbeat_pm"), f("hold_pm"), f("hold_beats"), f("perfect_ms"), f("good_ms"),
                f("good_pm"), f("stray_pm"), f("pour_ms"), f("pour_ready_ms"), f("pour_rate"), f("target_lo"), f("target_hi"), f("pour_tolerance"),
                f("track_weight_pct"), m.get("slag_pm").and_then(|x| x.as_i64()).unwrap_or(0))
        }
        "carve" => {
            // Woodworking's carve (Luke, 2026-11-07): two profiles of the same length, a blank to cut them from.
            let arr = |k: &str| -> Vec<i64> {
                m[k].as_array().unwrap_or_else(|| panic!("regents content: {what}'s carve has no {k}")).iter().map(|v| v.as_i64().unwrap()).collect()
            };
            let (l, r) = (arr("left_outline"), arr("right_outline"));
            assert!(!l.is_empty() && l.len() == r.len() && l.len() < 1000 && f("error_scale") > 0 && f("swing_ms") > 0 && f("deep_cut") > 0
                && f("fine_cut") > 0, "regents content: {what}'s carve cannot be played (two profiles of one length under 1000 rows, cuts and a scale)");
            format!("Minigame::Carve(carve::CarveParams {{ duration_ms: {}, swing_ms: {}, start_half: {}, start_jitter: {}, deep_cut: {}, fine_cut: {}, left_outline: &{:?}, right_outline: &{:?}, outline_vary: {}, error_scale: {}, hide_outline: {}, lay_cost_pm: {}, mirror: {} }})",
                f("duration_ms"), f("swing_ms"), f("start_half"), f("start_jitter"), f("deep_cut"), f("fine_cut"), l, r, f("outline_vary"), f("error_scale"),
                f("hide_outline"), f("lay_cost_pm"), f("mirror"))
        }
        "pull" => {
            // Herbalism's pull the root (Luke's H3, 2026-11-07; the trowel digging and cutting, 2026-11-08; loose or
            // packed stems, 2026-11-09: absent in a bake from before, so 0, both sides packed).
            let opt = |k: &str| m.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
            assert!(f("duration_ms") >= 50 && f("stroke_ms") >= 50 && f("target_plants") >= 1 && f("dig_pm") >= 1
                && (0..=1000).contains(&f("hold_pm")) && f("strain_rise") > 0 && f("strain_ease") > 0 && f("pull_rate") + f("pull_gain") > 0
                && (0..=900).contains(&f("snags")) && f("jump_lo") >= 0 && f("jump_hi") >= f("jump_lo") && (0..=1000).contains(&f("snap_keep_pm")),
                "regents content: {what}'s pull the root cannot be played (a stroke, a target of at least one stem, soil that digs, a strain that rises and eases, a root that comes up, jumps in order)");
            format!("Minigame::Pull(pull::PullParams {{ duration_ms: {}, stroke_ms: {}, target_plants: {}, dig_pm: {}, hold_pm: {}, strain_rise: {}, strain_ease: {}, pull_rate: {}, pull_gain: {}, snags: {}, jump_lo: {}, jump_hi: {}, show_depth: {}, snap_keep_pm: {}, loose_pm: {} }})",
                f("duration_ms"), f("stroke_ms"), f("target_plants"), f("dig_pm"), f("hold_pm"), f("strain_rise"), f("strain_ease"), f("pull_rate"),
                f("pull_gain"), f("snags"), f("jump_lo"), f("jump_hi"), f("show_depth"), f("snap_keep_pm"), opt("loose_pm").clamp(0, 1000))
        }
        "skin" => {
            // Skinning's cut line (Luke's H4, 2026-11-07; built 2026-11-10): drag the knife along it, off it tears.
            assert!(f("duration_ms") >= 50 && f("target_lines") >= 1 && (2..=20).contains(&f("points")) && (0..=300).contains(&f("wobble"))
                && f("near") >= 1 && f("reach") >= 1 && f("cut_speed") >= 1 && (0..=1000).contains(&f("tear_pm"))
                && (0..=1000).contains(&f("part_keep_pm")),
                "regents content: {what}'s cut line cannot be played (a target of at least one line, 2-20 points, a wobble under 300, a knife that cuts)");
            format!("Minigame::Skin(skin::SkinParams {{ duration_ms: {}, target_lines: {}, points: {}, wobble: {}, near: {}, reach: {}, cut_speed: {}, tear_pm: {}, part_keep_pm: {} }})",
                f("duration_ms"), f("target_lines"), f("points"), f("wobble"), f("near"), f("reach"), f("cut_speed"), f("tear_pm"), f("part_keep_pm"))
        }
        "shape" => {
            let outline: Vec<i64> = m["outline"].as_array().unwrap_or_else(|| panic!("regents content: {what}'s shape has no outline"))
                .iter().map(|v| v.as_i64().unwrap()).collect();
            assert!(!outline.is_empty() && f("error_scale") > 0, "regents content: {what}'s shape cannot be played");
            // The light tap (2026-11-05): absent in a bake from before it, so 0 (off).
            let opt = |k: &str| m.get(k).and_then(|x| x.as_i64()).unwrap_or(0);
            format!("Minigame::Shape(ShapeSeed {{ duration_ms: {}, swing_ms: {}, heat_ms: {}, reheat_ms: {}, start_height: {}, start_jitter: {}, hammer_drop: {}, spread_pct: {}, tap_drop: {}, tap_spread_pct: {}, outline: &{:?}, error_scale: {}{} }})",
                f("duration_ms"), f("swing_ms"), f("heat_ms"), f("reheat_ms"), f("start_height"), f("start_jitter"), f("hammer_drop"), f("spread_pct"),
                opt("tap_drop"), opt("tap_spread_pct"), outline, f("error_scale"),
                // The bands' rules (2026-11-05): each absent in an older bake, so 0 (off).
                ["max_reheats", "reheat_cost_pm", "hide_outline", "lay_cost_pm", "outline_vary", "red_ms", "crack_cost_pm",
                 "quench_lo_pm", "quench_hi_pm", "quench_bonus_pm", "quench_loss_pm"].iter().map(|k| format!(", {k}: {}", opt(k))).collect::<String>())
        }
        other => panic!("regents content: {what} has a minigame of kind '{other}' this server does not know"),
    }
}

pub fn regents_data() {
    let items = baked("item");
    let skills = baked("skill");
    let nodes = baked("node");
    let recipes = baked("recipe");
    let stations = baked("station");
    let roles = baked("role");
    let lessons = baked("lesson");
    let mut out = String::from("// @generated by build.rs from shared/content/regents/*.json — do not edit.\n");

    // THE ROLES (COMBAT_OVERHAUL.md §5): what a handle's shape carries. One is the plain one.
    out.push_str("pub static ROLES: &[RoleSeed] = &[\n");
    let mut role_ids: Vec<i64> = Vec::new();
    for r in &roles {
        let name = text(r, "name", "a role");
        role_ids.push(int(r, "id", &name));
        out.push_str(&format!("    RoleSeed {{ id: {}, key: {:?}, plain: {}, full_block: {}, threat_pct: {}, threat_rule: {:?}, threat_scope_rule: {:?}, drop_rule: {:?} }},\n",
            int(r, "id", &name), text(r, "key", &name), r["plain"].as_bool().unwrap_or(false), r["full_block"].as_bool().unwrap_or(false),
            int(r, "threat_pct", &name), text(r, "threat_rule", &name), text(r, "threat_scope_rule", &name), text(r, "drop_rule", &name)));
    }
    let plains = roles.iter().filter(|r| r["plain"].as_bool().unwrap_or(false)).count();
    assert!(roles.is_empty() || plains == 1, "regents content: one role is the plain one (a weapon whose handle names none), not {plains}");
    out.push_str("];\n\n");
    out.push_str("pub static ITEMS: &[ItemSeed] = &[\n");
    let mut item_ids: Vec<i64> = Vec::new();
    let mut part_items: Vec<(i64, String)> = Vec::new();
    let mut weapon_kits: Vec<(String, String)> = Vec::new();
    for it in &items {
        let name = text(it, "name", "an item");
        let tag = text(it, "tool_tag", &name);
        let tier = int(it, "tool_tier", &name);
        assert!(tag.is_empty() || tier >= 1, "regents content: the tool '{name}' works no tier");
        item_ids.push(int(it, "id", &name));
        let part = text(it, "part_tag", &name);
        if !part.is_empty() {
            part_items.push((int(it, "id", &name), part.clone()));
        }
        let kit = text(it, "weapon_kit", &name);
        if !kit.is_empty() {
            weapon_kits.push((name.clone(), kit.clone()));
        }
        // A handle's shape: its role, and the one kit it fits (an older bake: none).
        let role = it["role"].as_i64().unwrap_or(-1).max(0);
        assert!(role == 0 || role_ids.contains(&role), "regents content: {name}'s shape gives role {role}, which is no role");
        let fits = it["fits_kit"].as_str().unwrap_or("").to_string();
        if !fits.is_empty() {
            weapon_kits.push((name.clone(), fits.clone()));
        }
        out.push_str(&format!("    ItemSeed {{ id: {}, name: {name:?}, max_stack: {}, tool_tag: {tag:?}, tool_tier: {tier}, tool_speed_pct: {}, \
             weapon_kit: {kit:?}, weapon_damage_pct: {}, part_tag: {part:?}, handle_trait: {}, weapon_trait: {}, ammo_for: {:?}, \
             ammo_damage_pct: {}, role: {role}, fits_kit: {fits:?} }},\n",
            int(it, "id", &name), int(it, "max_stack", &name), int(it, "tool_speed_pct", &name), int(it, "weapon_damage_pct", &name),
            it["handle_trait"].as_i64().unwrap_or(-1).max(0), it["weapon_trait"].as_i64().unwrap_or(-1).max(0), text(it, "ammo_for", &name),
            it["ammo_damage_pct"].as_i64().unwrap_or(100)));
    }
    let item = |id: i64, what: &str| assert!(item_ids.contains(&id), "regents content: {what} names item {id}, which is not an item");

    out.push_str("];\n\npub static SKILLS: &[SkillSeed] = &[\n");
    let mut skill_ids: Vec<i64> = Vec::new();
    for s in &skills {
        let name = text(s, "name", "a skill");
        let curve: Vec<i64> = s["xp_to_rank"].as_array().unwrap_or_else(|| panic!("regents content: {name} has no xp_to_rank"))
            .iter().map(|v| v.as_i64().unwrap()).collect();
        assert!(curve.windows(2).all(|w| w[1] > w[0]), "regents content: {name}'s xp_to_rank does not rise");
        skill_ids.push(int(s, "id", &name));
        out.push_str(&format!("    SkillSeed {{ id: {}, key: {:?}, name: {name:?}, xp_to_rank: &{:?} }},\n", int(s, "id", &name), text(s, "key", &name), curve));
    }
    let skill = |id: i64, what: &str| assert!(skill_ids.contains(&id), "regents content: {what} trains skill {id}, which is not a skill");

    out.push_str("];\n\npub static NODES: &[NodeSeed] = &[\n");
    for n in &nodes {
        let name = text(n, "name", "a node");
        let (yld, rare, rare_pm, sk) = (int(n, "yield_item", &name), int(n, "rare_item", &name).max(0), int(n, "rare_permille", &name), int(n, "skill", &name));
        item(yld, &name);
        assert!(rare_pm == 0 || item_ids.contains(&rare), "regents content: {name} has a rare chance and no rare item");
        skill(sk, &name);
        let mg = minigame(&n["minigame"], &name);
        // None: AFK only: holding E works it AFK too. Pull: herbalism's round (2026-11-08). Skin: a carcass's (2026-11-10).
        assert!(mg == "Minigame::None" || mg.starts_with("Minigame::Chop") || mg.starts_with("Minigame::Crack") || mg.starts_with("Minigame::Pull") || mg.starts_with("Minigame::Skin"),
            "regents content: {name}'s round is not a gathering round");
        // Each model's footprint (cm), baked from the models (`NodeDef.radii_cm`); none: the reach is from the middle.
        let radii: Vec<i64> = n["radii_cm"].as_array().map(|a| a.iter().map(|v| v.as_i64().unwrap_or(0)).collect()).unwrap_or_default();
        assert!(radii.iter().all(|r| (0..=2000).contains(r)), "regents content: {name} has a model footprint out of 0-20 m: {radii:?}");
        // A cap and a whole-node round (a carcass's hides, 2026-11-10): absent in a bake from before, so none.
        let max_items = n.get("max_items").and_then(|x| x.as_i64()).unwrap_or(0);
        let whole_round = n.get("whole_round").and_then(|x| x.as_bool()).unwrap_or(false);
        assert!((0..=1000).contains(&max_items) && (!whole_round || (max_items >= 1 && mg != "Minigame::None")),
            "regents content: {name}'s cap is out of 0-1000, or it is worked whole in a round with no cap or no round");
        out.push_str(&format!(
            "    NodeSeed {{ id: {}, name: {name:?}, skill: {sk}, tier: {}, minigame: {mg}, yield_item: {yld}, tool_tag: {:?}, min_tool_tier: {}, \
             min_rank: {}, xp: {}, afk_ms: {}, deplete_permille: {}, regrow_ms: {}, rare_item: {rare}, rare_permille: {rare_pm}, radii_cm: &{:?}, \
             max_items: {max_items}, whole_round: {whole_round} }},\n",
            int(n, "id", &name), int(n, "tier", &name), text(n, "tool_tag", &name), int(n, "min_tool_tier", &name), int(n, "min_rank", &name),
            int(n, "xp", &name), int(n, "afk_ms_per_item", &name), int(n, "deplete_permille", &name), int(n, "regrow_ms", &name), radii));
    }

    out.push_str("];\n\npub static STATIONS: &[StationSeed] = &[\n");
    let mut station_keys: Vec<String> = Vec::new();
    for s in &stations {
        let name = text(s, "name", "a station");
        station_keys.push(text(s, "key", &name));
        out.push_str(&format!("    StationSeed {{ id: {}, key: {:?}, name: {name:?} }},\n", int(s, "id", &name), text(s, "key", &name)));
    }

    out.push_str("];\n\npub static RECIPES: &[RecipeSeed] = &[\n");
    for r in &recipes {
        let name = text(r, "name", "a recipe");
        let st = text(r, "station", &name);
        assert!(station_keys.contains(&st), "regents content: {name} is made at '{st}', which is no station");
        let sk = int(r, "skill", &name);
        skill(sk, &name);
        let ins: Vec<(i64, i64)> = r["inputs"].as_array().unwrap_or_else(|| panic!("regents content: {name} has no inputs"))
            .iter().map(|p| (p[0].as_i64().unwrap(), p[1].as_i64().unwrap())).collect();
        assert!(!ins.is_empty(), "regents content: {name} takes nothing");
        for (id, q) in &ins {
            item(*id, &name);
            assert!(*q >= 1, "regents content: {name} takes {q} of item {id}");
        }
        let output = int(r, "output", &name);
        item(output, &name);
        let mg = minigame(&r["minigame"], &name);
        assert!(mg == "Minigame::None" || mg.starts_with("Minigame::Smelt") || mg.starts_with("Minigame::Shape") || mg.starts_with("Minigame::Beat") || mg.starts_with("Minigame::Carve"), "regents content: {name}'s round is not a station round");
        let quality = int(r, "quality", &name);
        assert!(quality != 1 || mg != "Minigame::None", "regents content: {name}'s quality comes from a round it does not have");
        let slot = int(r, "part_slot", &name);
        assert!(slot < ins.len() as i64, "regents content: {name}'s part slot {slot} is past its inputs");
        assert!(slot < 0 || part_items.iter().any(|(id, _)| *id == ins[slot as usize].0),
            "regents content: {name}'s part slot is item {}, which is no part (set its `part_tag`)", if slot >= 0 { ins[slot as usize].0 } else { 0 });
        // Every input the player picks (MATERIALS.md step 3); a bake from before them: the one part slot.
        let slots: Vec<i64> = match r["part_slots"].as_array() {
            Some(a) => a.iter().map(|v| v.as_i64().unwrap_or(-1)).collect(),
            None if slot >= 0 => vec![slot],
            None => vec![],
        };
        for s in &slots {
            assert!(*s >= 0 && *s < ins.len() as i64, "regents content: {name}'s part slot {s} is past its inputs");
            assert!(part_items.iter().any(|(id, _)| *id == ins[*s as usize].0), "regents content: {name}'s part slot {s} is item {}, which is no part", ins[*s as usize].0);
        }
        assert!(slots.first().copied().unwrap_or(-1) == slot, "regents content: {name}'s part_slot must be the first of its part_slots");
        let slots: Vec<i32> = slots.iter().map(|s| *s as i32).collect();
        out.push_str(&format!(
            "    RecipeSeed {{ id: {}, name: {name:?}, station: {st:?}, skill: {sk}, inputs: &{:?}, output: {output}, output_qty: {}, xp: {}, min_rank: {}, \
             afk_ms: {}, minigame: {mg}, quality: {quality}, afk_quality: {}, part_slot: {slot}, part_slots: &{slots:?} }},\n",
            int(r, "id", &name), ins.iter().map(|(a, b)| (*a as u32, *b as u32)).collect::<Vec<_>>(), int(r, "output_qty", &name), int(r, "xp", &name),
            int(r, "min_rank", &name), int(r, "afk_ms", &name), int(r, "afk_quality", &name)));
    }
    out.push_str("];\n\npub static KITS: &[KitSeed] = &[\n");
    let mut kit_keys: Vec<String> = Vec::new();
    // A casting kit's abilities must each be a spell's (checked with the spells below).
    let mut casting_kits: Vec<(String, Vec<u32>)> = Vec::new();
    for k in &baked("kit") {
        let name = text(k, "name", "a kit");
        let key = text(k, "key", &name);
        let sk = int(k, "skill", &name);
        skill(sk, &name);
        let light: Vec<u32> = k["light"].as_array().unwrap_or_else(|| panic!("regents content: {name} has no light combo"))
            .iter().map(|v| v.as_i64().unwrap() as u32).collect();
        assert!(!light.is_empty(), "regents content: the {name} kit has no light combo");
        let skills: Vec<(u32, u32)> = k["skills"].as_array().unwrap_or_else(|| panic!("regents content: {name} has no skills list"))
            .iter().map(|p| (p[0].as_i64().unwrap() as u32, p[1].as_i64().unwrap() as u32)).collect();
        let locks: Vec<(u32, u32)> = k["locks"].as_array().unwrap_or_else(|| panic!("regents content: {name} has no locks (re-bake)"))
            .iter().map(|p| (p[0].as_i64().unwrap() as u32, p[1].as_i64().unwrap() as u32)).collect();
        for a in light.iter().chain(skills.iter().map(|(a, _)| a)) {
            assert!(locks.iter().any(|(l, ms)| l == a && *ms > 0), "regents content: the {name} kit's ability {a} has no lock");
        }
        // Abilities no block or parry stops (a foe's finisher); an older bake has none.
        let unblockable: Vec<u32> = k["unblockable"].as_array().map_or(Vec::new(), |a| a.iter().map(|v| v.as_i64().unwrap() as u32).collect());
        for a in &unblockable {
            assert!(light.contains(a) || skills.iter().any(|(s, _)| s == a),
                "regents content: the {name} kit lists {a} as unblockable, which is not its ability");
        }
        // Each step's follow-through (COMBAT_OVERHAUL.md §3), one per step of the string.
        let follow: Vec<u32> = k["follow_ms"].as_array().unwrap_or_else(|| panic!("regents content: {name} has no follow-throughs (re-bake)"))
            .iter().map(|v| v.as_i64().unwrap().max(0) as u32).collect();
        assert_eq!(follow.len(), light.len(), "regents content: the {name} kit needs a follow-through per step of its string");
        // THE ROLE MAP (COMBAT_OVERHAUL.md §5): per role, the string's last hit; the plain role's is the string's last.
        let mut role_map = String::new();
        for kr in k["roles"].as_array().cloned().unwrap_or_default() {
            let role = kr["role"].as_i64().unwrap_or(0);
            let fin = kr["finisher"].as_i64().unwrap_or(0) as u32;
            assert!(role_ids.contains(&role), "regents content: the {name} kit's role map names role {role}, which is no role");
            assert!(locks.iter().any(|(l, ms)| *l == fin && *ms > 0), "regents content: the {name} kit's last hit {fin} has no lock (re-bake)");
            let plain = roles.iter().any(|r| r["id"].as_i64() == Some(role) && r["plain"].as_bool().unwrap_or(false));
            assert!(!plain || light.last() == Some(&fin), "regents content: the {name} kit's plain role must end the string with its last step");
            assert!(plain || (!light.contains(&fin) && !skills.iter().any(|(s, _)| *s == fin)),
                "regents content: the {name} kit's role {role} ends with {fin}, a step or a skill already");
            let f = |k: &str| kr.get(k).and_then(|x| x.as_f64()).unwrap_or(0.0) as f32;
            role_map.push_str(&format!("RoleFinisher {{ role: {role}, ability: {fin}, stagger_pct: {}, heal: {:?}f32, heal_radius_m: {:?}f32 }}, ",
                kr["stagger_pct"].as_i64().unwrap_or(100).max(0), f("heal"), f("heal_radius_m")));
        }
        // What its abilities do when they land unblocked (`KitHit`, Luke 2026-11-10); absent in an older bake.
        let mut hit_map = String::new();
        for kh in k["hits"].as_array().cloned().unwrap_or_default() {
            let ab = kh["ability"].as_i64().unwrap_or(0) as u32;
            assert!(light.contains(&ab) || skills.iter().any(|(s, _)| *s == ab) || k["roles"].as_array().is_some_and(|rs| rs.iter().any(|r| r["finisher"].as_i64() == Some(ab as i64))),
                "regents content: the {name} kit's hit entry is for {ab}, which is not its ability");
            let push = kh.get("push_mps").and_then(|x| x.as_f64()).unwrap_or(0.0).max(0.0) as f32;
            let status = kh["status"].as_i64().unwrap_or(0).clamp(0, 255) as u8;
            let status_ms = kh["status_ms"].as_i64().unwrap_or(0).max(0) as u32;
            assert!(push > 0.0 || (status > 0 && status_ms > 0), "regents content: the {name} kit's hit entry for {ab} does nothing");
            hit_map.push_str(&format!("KitHitSeed {{ ability: {ab}, push_mps: {push:?}f32, status: {status}, status_ms: {status_ms} }}, "));
        }
        kit_keys.push(key.clone());
        out.push_str(&format!("    KitSeed {{ id: {}, key: {key:?}, skill: {sk}, light: &{light:?}, follow_ms: &{follow:?}, skills: &{skills:?}, \
             locks: &{locks:?}, draw_full_ms: {}, resource: {}, unblockable: &{unblockable:?}, roles: &[{role_map}], hits: &[{hit_map}] }},\n",
            int(k, "id", &name), k["draw_full_ms"].as_i64().unwrap_or(0), k["resource"].as_i64().unwrap_or(0).max(0)));
        if k["resource"].as_i64().unwrap_or(0) > 0 {
            casting_kits.push((name.clone(), light.iter().copied().chain(skills.iter().map(|(a, _)| *a)).collect()));
        }
    }
    for (item, kit) in &weapon_kits {
        assert!(kit_keys.contains(kit), "regents content: the weapon {item} fights with kit '{kit}', which is no kit");
    }
    out.push_str("];\n\npub static FOES: &[FoeSeed] = &[\n");
    let mut foe_kinds: Vec<i64> = Vec::new();
    for f in &baked("foe") {
        let name = text(f, "name", "a foe");
        let key = text(f, "key", &name);
        assert!(!key.is_empty(), "regents content: the foe {name} has no key (its level points' kind)");
        let kind = int(f, "kind", &name);
        assert!((103..=119).contains(&kind), "regents content: the foe {name} is kind {kind}; a foe's kind is 103-119 (genre::regents::FOE_KINDS)");
        assert!(!foe_kinds.contains(&kind), "regents content: two foes are kind {kind}");
        foe_kinds.push(kind);
        // A creature that never fights (hunting, 2026-11-09: a deer) has no kit; its brain is its character's.
        let fights = f["fights"].as_bool().unwrap_or(true);
        let kit = f["kit"].as_str().unwrap_or("").to_string();
        assert!(!fights || kit_keys.contains(&kit), "regents content: the foe {name} fights with kit '{kit}', which is no kit");
        let brain = f["brain"].as_str().filter(|b| !b.is_empty()).unwrap_or("regents/foe").to_string();
        let hp = int(f, "hp", &name);
        assert!(hp > 0, "regents content: the foe {name} has no health");
        // Its loot table (DECISIONS #268): the foundation's build checks the table itself.
        let loot_table = f["loot_table"].as_i64().unwrap_or(-1).max(0);
        // What its kill leaves (skinning, 2026-11-09): a carcass node's id, or 0.
        let carcass = f["carcass"].as_i64().unwrap_or(-1).max(0);
        out.push_str(&format!("    FoeSeed {{ id: {}, name: {name:?}, key: {key:?}, kind: {kind}, kit: {kit:?}, fights: {fights}, brain: {brain:?}, hp: {hp}, damage_pct: {}, xp_pct: {}, \
             loot_table: {loot_table}, family: {:?}, boss: {}, poise: {}, carcass: {carcass} }},\n", int(f, "id", &name), int(f, "damage_pct", &name), int(f, "xp_pct", &name),
            f["family"].as_str().unwrap_or(""), f["boss"].as_bool().unwrap_or(false), f["poise"].as_i64().unwrap_or(0).max(0)));
    }
    out.push_str("];\n\npub static SPELLS: &[SpellSeed] = &[\n");
    // THE STAFF'S SPELLS (owner, 2026-10-20): how each casting ability lands.
    let mut spell_abilities: Vec<u32> = Vec::new();
    for s in &baked("spell") {
        let name = text(s, "name", "a spell");
        let ability = int(s, "ability", &name);
        assert!(ability > 0, "regents content: the spell {name} is no ability's");
        assert!(!spell_abilities.contains(&(ability as u32)), "regents content: two spells are ability {ability}'s");
        spell_abilities.push(ability as u32);
        let kind = int(s, "kind", &name);
        assert!((0..=3).contains(&kind), "regents content: the spell {name} is of kind {kind} (0 bolt, 1 area, 2 blink, 3 cone)");
        let body = s["body"].as_i64().unwrap_or(-1).max(0);
        assert!(kind != 0 || body > 0, "regents content: the bolt {name} has no missile (body)");
        let f = |k: &str| s.get(k).and_then(|x| x.as_f64()).unwrap_or_else(|| panic!("regents content: the spell {name} has no '{k}'"));
        out.push_str(&format!("    SpellSeed {{ ability: {ability}, kind: {kind}, cost: {:?}f32, cast_ms: {}, cast_while_moving: {}, body: {body}, \
             speed: {:?}f32, splash_m: {:?}f32, splash_pct: {}, burn_dps: {:?}f32, burn_ms: {}, radius_m: {:?}f32, delay_ms: {}, \
             angle_deg: {:?}f32, push_mps: {:?}f32, status: {}, status_ms: {} }},\n",
            f("cost") as f32, int(s, "cast_ms", &name), s["cast_while_moving"].as_bool().unwrap_or(true),
            f("speed_mps") as f32, f("splash_m") as f32, int(s, "splash_pct", &name), f("burn_dps") as f32, int(s, "burn_ms", &name),
            f("radius_m") as f32, int(s, "delay_ms", &name), f("angle_deg") as f32, f("push_mps") as f32,
            int(s, "status", &name), int(s, "status_ms", &name)));
    }
    for (kit, abilities) in &casting_kits {
        for a in abilities {
            assert!(spell_abilities.contains(a), "regents content: the casting kit {kit}'s ability {a} is no spell's");
        }
    }
    out.push_str("];\n");

    // THE TUTORIAL'S LESSONS (Luke, 2026-11-01), in order: each its deed (`LessonDef.Done`) and the item it wants.
    out.push_str("\npub static LESSONS: &[LessonSeed] = &[\n");
    let mut sorted: Vec<&serde_json::Value> = lessons.iter().collect();
    sorted.sort_by_key(|l| l["order"].as_i64().unwrap_or(0));
    let mut orders: Vec<i64> = Vec::new();
    for l in sorted {
        let name = text(l, "name", "a lesson");
        let order = int(l, "order", &name);
        assert!(!orders.contains(&order), "regents content: two lessons are number {order} in the run");
        orders.push(order);
        let deed = int(l, "done_when", &name);
        assert!((0..=9).contains(&deed), "regents content: the lesson {name}'s deed {deed} is none the server sees");
        let item = l["item"].as_i64().unwrap_or(-1).max(0);
        assert!(item == 0 || items.iter().any(|i| i["id"].as_i64() == Some(item)), "regents content: the lesson {name} wants item {item}, which is no item");
        out.push_str(&format!("    LessonSeed {{ id: {}, order: {order}, deed: {deed}, item: {item}, any_of_its_kind: {} }},\n",
            int(l, "id", &name), l["any_of_its_kind"].as_bool().unwrap_or(false)));
    }
    out.push_str("];\n");
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("regents_data.rs"), out).unwrap();
}
