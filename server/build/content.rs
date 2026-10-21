// THE BAKED CONTENT (docs/CONTENT_TOOLING_SPEC.md §1.2, DECISIONS #199). Content is edited as
// `.tres` resources in Godot (`foundation/content/`, `game/<genre>/content/`) and baked by
// `tools/bake_content.gd` to `shared/content/<owner>/<type>.json`, with a manifest of hashes. This
// step refuses to build while the bake is stale, naming the file: a `.tres` changed or added since
// the bake, or a baked file edited by hand. Then it compiles what the module seeds:
//
//   shared/content/<owner>/ability.json -> $OUT_DIR/content.rs (`ABILITIES`, seeded at init)
//   shared/content/<owner>/status.json  -> $OUT_DIR/statuses.rs (`status::STATUSES`, DECISIONS #206)
//   movement profiles and characters    -> $OUT_DIR/movement_limits.rs (each kind's Tier A bound)
//   characters' abilities               -> $OUT_DIR/kind_abilities.rs (what each kind may use)
//   characters players may choose       -> $OUT_DIR/content.rs (`PLAYABLE_KINDS`, DECISIONS #217)
//   shared/content/<owner>/hold.json    -> $OUT_DIR/holds.rs (`hold::HOLDS`, DECISIONS #209)
//   shared/content/<owner>/body.json    -> $OUT_DIR/bodies.rs (`body::BODIES`, DECISIONS #246)
//   shared/content/<owner>/loot_table.json -> $OUT_DIR/loot_tables.rs (`loot::LOOT_TABLES`, DECISIONS #268)
//   shared/content/<owner>/resource.json -> $OUT_DIR/resources.rs (`resource::RESOURCES`, DECISIONS #270)
//   shared/content/<owner>/trait.json   -> $OUT_DIR/traits.rs (`traits::TRAITS`, DECISIONS #275)
//
// The foundation's content always; a genre's only when shared/game.json lists it.
// UMF_CONTENT_ROOT stands in for the repo root (tests/content_test.sh builds against a copy).

use std::{env, fs, path::{Path, PathBuf}};

/// FNV-1a, 32 bits, as hex: the manifest's hash (tools/bake_content.gd computes the same).
fn fnv(bytes: &[u8]) -> String {
    let mut h: u32 = 2166136261;
    for b in bytes {
        h = (h ^ *b as u32).wrapping_mul(16777619);
    }
    format!("{h:08x}")
}

fn tres_under(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    for entry in rd.flatten() {
        let p = entry.path();
        if p.is_dir() {
            tres_under(&p, out);
        } else if p.extension().and_then(|e| e.to_str()) == Some("tres") {
            out.push(p);
        }
    }
}

pub fn run(listed: &[String]) {
    println!("cargo:rerun-if-env-changed=UMF_CONTENT_ROOT");
    let root = PathBuf::from(env::var("UMF_CONTENT_ROOT").unwrap_or_else(|_| "..".to_string()));
    let manifest_path = root.join("shared/content/manifest.json");
    println!("cargo:rerun-if-changed={}", manifest_path.display());
    let mut dirs: Vec<PathBuf> = vec![root.join("foundation/content")];
    for g in listed {
        dirs.push(root.join(format!("game/{g}/content")));
    }
    for d in &dirs {
        println!("cargo:rerun-if-changed={}", d.display());
    }
    let manifest: serde_json::Value = match fs::read_to_string(&manifest_path) {
        Ok(t) => serde_json::from_str(&t).expect("shared/content/manifest.json is malformed: bake again (tools/bake_content.gd)"),
        Err(_) => serde_json::json!({ "outputs": {} }),
    };
    // The baked layout this reader knows (tools/bake_content.gd FORMAT). Another is refused, not misread.
    const FORMAT: u64 = 1;
    let fmt = manifest["format"].as_u64().unwrap_or(FORMAT);
    assert!(fmt == FORMAT, "shared/content/manifest.json is bake format {fmt}; this server reads format {FORMAT}:         update server/build/content.rs with tools/bake_content.gd, or bake with the matching version");
    let outputs = manifest["outputs"].as_object().cloned().unwrap_or_default();
    let mut baked: Vec<String> = Vec::new();
    let mut abilities: Vec<(u64, String)> = Vec::new();
    // Hot rules: (key, kind, number, text, min, max) as declared, then this game's overrides.
    let mut rules: Vec<(String, String, f64, String, f64, f64)> = Vec::new();
    let mut overrides: Vec<(String, f64, String, String)> = Vec::new();
    // Movement profiles by id; characters: (kind, profile id or -1).
    let mut profiles: Vec<Profile> = Vec::new();
    // Statuses: (owner, content id, the baked item).
    let mut statuses: Vec<(String, i64, serde_json::Value)> = Vec::new();
    // Holds: (owner, the baked item).
    let mut holds: Vec<(String, serde_json::Value)> = Vec::new();
    // Bodies (DECISIONS #246): (owner, the baked item).
    let mut bodies: Vec<(String, serde_json::Value)> = Vec::new();
    // Loot tables (DECISIONS #268): (owner, the baked item); and every baked item's id, for their links.
    let mut loot_tables: Vec<(String, serde_json::Value)> = Vec::new();
    let mut item_ids: Vec<u64> = Vec::new();
    // Resources (DECISIONS #270): (owner, the baked item).
    let mut resources: Vec<(String, serde_json::Value)> = Vec::new();
    // Traits (DECISIONS #275): (owner, the baked item).
    let mut traits: Vec<(String, serde_json::Value)> = Vec::new();
    let mut characters: Vec<(u64, i64)> = Vec::new();
    // Each character's kind and the ability ids it lists (DECISIONS #207).
    let mut kind_abilities: Vec<(u64, Vec<i64>)> = Vec::new();
    // The kinds a player may choose to play (DECISIONS #217): a character marked `playable`.
    let mut playable: Vec<u64> = Vec::new();
    for (out, info) in &outputs {
        let owner = info["owner"].as_str().unwrap_or("");
        if owner != "foundation" && !listed.iter().any(|g| g == owner) {
            continue; // a genre this game is not made of
        }
        let path = root.join(out);
        println!("cargo:rerun-if-changed={}", path.display());
        let bytes = fs::read(&path)
            .unwrap_or_else(|_| panic!("{out} is missing: bake the content (tools/bake_content.gd)"));
        assert!(
            fnv(&bytes) == info["hash"].as_str().unwrap_or(""),
            "{out} was edited by hand, or the bake did not finish. Content is edited in its .tres \
             files in Godot; bake again (tools/bake_content.gd)"
        );
        for (src, h) in info["sources"].as_object().cloned().unwrap_or_default() {
            let b = fs::read(root.join(&src))
                .unwrap_or_else(|_| panic!("{src} was baked but is gone: bake again (tools/bake_content.gd)"));
            assert!(
                fnv(&b) == h.as_str().unwrap_or(""),
                "{src} changed since the last bake: bake (tools/bake_content.gd), then build again"
            );
            baked.push(src);
        }
        let doc: serde_json::Value = serde_json::from_slice(&bytes).expect("a baked file is not JSON: bake again");
        assert!(doc["format"].as_u64() == Some(FORMAT), "{out} is not bake format {FORMAT}: bake again (tools/bake_content.gd)");
        if info["type"] == "rules" {
            for set in doc["items"].as_array().cloned().unwrap_or_default() {
                for r in set["rules"].as_array().cloned().unwrap_or_default() {
                    let s = |k: &str| r[k].as_str().unwrap_or("").to_string();
                    let f = |k: &str| r[k].as_f64().unwrap_or_else(|| panic!("{out}: rule {} has no {k}", s("key")));
                    rules.push((s("key"), s("kind"), f("number"), s("text"), f("min"), f("max")));
                }
                for o in set["overrides"].as_array().cloned().unwrap_or_default() {
                    overrides.push((o["key"].as_str().unwrap_or("").to_string(), o["number"].as_f64().unwrap_or(0.0),
                        o["text"].as_str().unwrap_or("").to_string(), out.clone()));
                }
            }
        }
        if info["type"] == "movement" {
            for p in doc["items"].as_array().cloned().unwrap_or_default() {
                let f = |k: &str| p[k].as_f64().unwrap_or(0.0);
                let lift = if f("flap_charges") > 0.0 { f("jump_velocity").max(f("flap_velocity")) } else { f("jump_velocity") };
                profiles.push(Profile { id: p["id"].as_i64().unwrap_or(-1), run: f("run_speed"), sprint: f("sprint_speed"),
                    dash: f("dash_impulse").max(0.0), lift, accel: f("acceleration"), dash_ticks: f("dash_ticks"),
                    dash_cooldown: f("dash_cooldown_ticks") });
            }
        }
        if info["type"] == "status" {
            for s in doc["items"].as_array().cloned().unwrap_or_default() {
                statuses.push((owner.to_string(), s["id"].as_i64().unwrap_or(-1), s));
            }
        }
        if info["type"] == "hold" {
            for h in doc["items"].as_array().cloned().unwrap_or_default() {
                holds.push((owner.to_string(), h));
            }
        }
        if info["type"] == "body" {
            for b in doc["items"].as_array().cloned().unwrap_or_default() {
                bodies.push((owner.to_string(), b));
            }
        }
        if info["type"] == "loot_table" {
            for t in doc["items"].as_array().cloned().unwrap_or_default() {
                loot_tables.push((owner.to_string(), t));
            }
        }
        if info["type"] == "resource" {
            for r in doc["items"].as_array().cloned().unwrap_or_default() {
                resources.push((owner.to_string(), r));
            }
        }
        if info["type"] == "trait" {
            for t in doc["items"].as_array().cloned().unwrap_or_default() {
                traits.push((owner.to_string(), t));
            }
        }
        if info["type"] == "item" {
            for it in doc["items"].as_array().cloned().unwrap_or_default() {
                if let Some(id) = it["id"].as_u64() {
                    item_ids.push(id);
                }
            }
        }
        if info["type"] == "character" {
            for c in doc["items"].as_array().cloned().unwrap_or_default() {
                characters.push((c["kind"].as_u64().unwrap_or(0), c["movement"].as_i64().unwrap_or(-1)));
                let listed: Vec<i64> = c["abilities"].as_array().cloned().unwrap_or_default().iter().filter_map(|a| a.as_i64()).collect();
                kind_abilities.push((c["kind"].as_u64().unwrap_or(0), listed));
                let kind = c["kind"].as_u64().unwrap_or(0);
                if c["playable"].as_bool().unwrap_or(false) && !playable.contains(&kind) {
                    assert!(kind <= 255, "a playable character has kind {kind}: kinds are 0-255");
                    playable.push(kind);
                }
            }
        }
        if info["type"] == "ability" {
            for it in doc["items"].as_array().cloned().unwrap_or_default() {
                let id = it["ability_id"].as_u64().expect("an ability without an ability_id");
                let f = |k: &str| it[k].as_f64().unwrap_or_else(|| panic!("{out}: ability {id} has no {k}"));
                // A judged ability (DECISIONS #226) says so in its row, with its sweep: the module and
                // the referee both read it there (and an admin's `define_ability` can make one).
                let mut data = if it["judged"].as_bool().unwrap_or(false) {
                    serde_json::json!({ "name": it["name"].as_str().unwrap_or(""), "judged": true,
                        "reach": it["reach"].as_f64().unwrap_or(0.0), "radius": it["radius"].as_f64().unwrap_or(0.35),
                        "height": it["height"].as_f64().unwrap_or(0.6) })
                } else {
                    serde_json::json!({ "name": it["name"].as_str().unwrap_or("") })
                };
                // One that throws its user's body forward (DECISIONS #232) says so too: the user's
                // client, and a referee driving a bot, dash it as the wind-up ends.
                if it["lunges"].as_bool().unwrap_or(false) {
                    data["lunges"] = serde_json::Value::Bool(true);
                }
                let data = data.to_string();
                abilities.push((id, format!(
                    "    AbilitySeed {{ ability_id: {id}, cooldown_ms: {}, range: {:?}f32, wind_up_ms: {}, damage: {:?}f32, data: {data:?} }},\n",
                    f("cooldown_ms") as u32, f("range") as f32, f("wind_up_ms") as u32, f("damage") as f32
                )));
            }
        }
    }
    // Every .tres in a content folder was baked: new content is not left out silently.
    for d in &dirs {
        let mut found = Vec::new();
        tres_under(d, &mut found);
        for p in found {
            let rel = p.strip_prefix(&root).unwrap_or(&p).to_string_lossy().replace('\\', "/");
            assert!(baked.contains(&rel), "{rel} is content that was never baked: bake (tools/bake_content.gd), then build again");
        }
    }
    abilities.sort_by_key(|(id, _)| *id);
    for w in abilities.windows(2) {
        assert!(w[0].0 != w[1].0, "two abilities have id {} (the foundation's and a genre's?): give one another id", w[0].0);
    }
    hot_rules(rules, overrides);
    movement_limits(&root, &profiles, &characters);
    // The statuses first: a hold links to them, and a game missing one says so in their terms.
    status_table(statuses.clone(), listed);
    hold_table(&holds, &statuses, listed);
    body_table(&bodies);
    loot_table(&loot_tables, &item_ids);
    resource_table(&resources);
    trait_table(&traits);
    kind_ability_table(kind_abilities, &abilities.iter().map(|(id, _)| *id as i64).collect::<Vec<_>>());
    let mut src = String::from(
        "// @generated by build.rs from shared/content/ (tools/bake_content.gd) — do not edit.\n\
         /// One ability, as the module seeds it into `ability_def` at init.\n\
         pub struct AbilitySeed { pub ability_id: u32, pub cooldown_ms: u32, pub range: f32, pub wind_up_ms: u32, pub damage: f32, pub data: &'static str }\n\
         /// Every ability: the foundation's and this game's genres', by id.\n\
         pub const ABILITIES: &[AbilitySeed] = &[\n",
    );
    for (_, line) in &abilities {
        src.push_str(line);
    }
    src.push_str("];\n");
    playable.sort();
    src.push_str(&format!(
        "/// The kinds a player may choose to play (DECISIONS #217): every character marked playable.\n\
         pub const PLAYABLE_KINDS: &[u8] = &[{}];\n\
         /// Whether a player may choose to be a `kind`.\n\
         pub fn is_playable(kind: u8) -> bool {{ PLAYABLE_KINDS.contains(&kind) }}\n",
        playable.iter().map(|k| k.to_string()).collect::<Vec<_>>().join(", ")));
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("content.rs"), src).unwrap();
}

/// The hot rules (DECISIONS #201) -> $OUT_DIR/hot_rules.rs: `ALL` (every rule with THIS GAME's
/// default: its declared value, or a listed genre's override) and one module per owner naming each
/// (`hot::foundation::INTERACT_RANGE_M`), so a misspelt rule does not build.
fn hot_rules(mut rules: Vec<(String, String, f64, String, f64, f64)>, overrides: Vec<(String, f64, String, String)>) {
    rules.sort_by(|a, b| a.0.cmp(&b.0));
    for w in rules.windows(2) {
        assert!(w[0].0 != w[1].0, "the hot rule '{}' is declared twice: bake again (tools/bake_content.gd says where)", w[0].0);
    }
    let mut seen: Vec<String> = Vec::new();
    for (key, number, text, from) in &overrides {
        let Some(r) = rules.iter_mut().find(|r| &r.0 == key) else {
            panic!("{from} overrides '{key}', which this game has no rule for (is its genre listed in shared/game.json?)");
        };
        assert!(!seen.contains(key), "'{key}' is overridden twice in this game: a game sets each rule once");
        seen.push(key.clone());
        if r.1 != "text" {
            assert!(*number >= r.4 && *number <= r.5, "{from}: '{key}' = {number} is outside {}..{}", r.4, r.5);
        }
        r.2 = *number;
        r.3 = text.clone();
    }
    let kind = |k: &str| match k {
        "number" => "Kind::Number",
        "integer" => "Kind::Integer",
        "flag" => "Kind::Flag",
        "text" => "Kind::Text",
        other => panic!("a hot rule of kind '{other}': this server knows number, integer, flag, text"),
    };
    let mut src = String::from("// @generated by build.rs from shared/content/*/rules.json (tools/bake_content.gd) — do not edit.\n\
        /// Every hot rule, with this game's default (its declared value, or a genre's override), by key.\n\
        pub const ALL: &[Rule] = &[\n");
    for (key, k, number, text, min, max) in &rules {
        src.push_str(&format!("    Rule {{ key: {key:?}, kind: {}, number: {number:?}, text: {text:?}, min: {min:?}, max: {max:?} }},\n", kind(k)));
    }
    src.push_str("];\n");
    let mut owners: Vec<String> = rules.iter().map(|r| r.0.split('.').next().unwrap_or("").to_string()).collect();
    owners.dedup();
    for owner in owners {
        src.push_str(&format!("/// The `{owner}` rules, by name.\npub mod {owner} {{\n"));
        for (i, r) in rules.iter().enumerate() {
            if let Some(name) = r.0.strip_prefix(&format!("{owner}.")) {
                src.push_str(&format!("    pub const {}: &super::Rule = &super::ALL[{i}];\n", name.to_uppercase()));
            }
        }
        src.push_str("}\n");
    }
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("hot_rules.rs"), src).unwrap();
}

/// A movement profile, as a kind's Tier A bound needs it.
struct Profile { id: i64, run: f64, sprint: f64, dash: f64, lift: f64, accel: f64, dash_ticks: f64, dash_cooldown: f64 }

/// A kind's bound: (run, sprint, dash, lift, dash window, dash cooldown). The dash's WINDOW is the client
/// frames its burst may show: it lasts `dash_ticks`, and its extra speed bleeds off at the acceleration's
/// rate, whichever is longer; its cooldown, the frames before the next (DECISIONS #256).
fn bound_of(p: &Profile, hz: f64) -> (f64, f64, f64, f64, f64, f64) {
    if p.dash <= 0.0 {
        return (p.run, p.sprint, 0.0, p.lift, 0.0, 0.0);
    }
    (p.run, p.sprint, p.dash, p.lift, p.dash_ticks.max((p.dash / p.accel.max(1.0) * hz).ceil()), p.dash_cooldown)
}

/// How fast a kind of entity may claim to move in a Tier A world (DECISIONS #205) -> $OUT_DIR/
/// movement_limits.rs. A kind's bound is the widest of its characters': a character with a movement
/// profile brings the profile's run, sprint, dash and lift; one without brings the default's
/// (shared/movement_config.json). A kind no character with a profile uses keeps the default. Its dash
/// counts only inside a dash's window (#256): the longest of its characters', after the shortest cooldown.
fn movement_limits(root: &Path, profiles: &[Profile], characters: &[(u64, i64)]) {
    let cfg_path = root.join("shared/movement_config.json");
    println!("cargo:rerun-if-changed={}", cfg_path.display());
    let cfg: serde_json::Value = serde_json::from_str(&fs::read_to_string(&cfg_path).expect("shared/movement_config.json"))
        .expect("shared/movement_config.json is not JSON");
    let g = |k: &str| cfg[k].as_f64().unwrap_or(0.0);
    let hz = g("client_tick_hz");
    let default = bound_of(&Profile { id: -1, run: g("run_speed"), sprint: g("sprint_speed"), dash: g("dash_impulse").max(0.0),
        lift: if g("flap_charges") > 0.0 { g("jump_velocity").max(g("flap_velocity")) } else { g("jump_velocity") },
        accel: g("acceleration"), dash_ticks: g("dash_ticks"), dash_cooldown: g("dash_cooldown_ticks") }, hz);
    let mut kinds: Vec<(u64, (f64, f64, f64, f64, f64, f64))> = Vec::new();
    let mut profiled: Vec<u64> = Vec::new();
    for (kind, pid) in characters {
        let lim = match profiles.iter().find(|p| p.id == *pid) {
            Some(p) => {
                profiled.push(*kind);
                bound_of(p, hz)
            }
            None => {
                assert!(*pid < 0, "a character links to movement profile {pid}, which is not baked content");
                default
            }
        };
        match kinds.iter_mut().find(|k| k.0 == *kind) {
            Some(k) => {
                // The shortest cooldown among those that dash at all.
                let cool = match (k.1 .2 > 0.0, lim.2 > 0.0) {
                    (true, true) => k.1 .5.min(lim.5),
                    (false, true) => lim.5,
                    _ => k.1 .5,
                };
                k.1 = (k.1 .0.max(lim.0), k.1 .1.max(lim.1), k.1 .2.max(lim.2), k.1 .3.max(lim.3), k.1 .4.max(lim.4), cool)
            }
            None => kinds.push((*kind, lim)),
        }
    }
    kinds.retain(|k| profiled.contains(&k.0));
    kinds.sort_by_key(|k| k.0);
    let lit = |l: &(f64, f64, f64, f64, f64, f64)| format!(
        "MovementLimits {{ run: {:?}f32, sprint: {:?}f32, burst: 0.0f32, lift: {:?}f32, dash: {:?}f32, dash_frames: {:?}f32, dash_cooldown_frames: {:?}f32 }}",
        l.0 as f32, l.1 as f32, l.3 as f32, l.2 as f32, l.4 as f32, l.5 as f32);
    let mut src = format!(
        "// @generated by build.rs from shared/content (movement profiles, characters) - do not edit.
         /// A kind's Tier A movement bound: the fastest a client of it may claim to go. `burst` is what
         /// pushes add (0 here); `dash` is its dash's, which counts only for `dash_frames` client frames
         /// after a dash press, and a press only `dash_cooldown_frames` after the last (DECISIONS #256).
         #[derive(Clone, Copy, Debug, PartialEq)]
         pub struct MovementLimits {{ pub run: f32, pub sprint: f32, pub burst: f32, pub lift: f32, pub dash: f32, pub dash_frames: f32, pub dash_cooldown_frames: f32 }}
         /// The default's (shared/movement_config.json): every kind no profiled character uses.
         pub const DEFAULT_LIMITS: MovementLimits = {};
         /// Kinds with a movement profile, by kind.
         pub const KIND_LIMITS: &[(u8, MovementLimits)] = &[
",
        lit(&default)
    );
    for (kind, l) in &kinds {
        src.push_str(&format!("    ({kind}, {}),
", lit(l)));
    }
    src.push_str("];
/// A kind's bound.
pub fn movement_limits(kind: u8) -> MovementLimits {
    KIND_LIMITS.iter().find(|k| k.0 == kind).map(|k| k.1).unwrap_or(DEFAULT_LIMITS)
}
");
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("movement_limits.rs"), src).unwrap();
}

/// The statuses (DECISIONS #206) -> $OUT_DIR/statuses.rs: `STATUSES`, one per number, for the module
/// (`crate::status`). The foundation's are 0-99 and a genre's 100-255; a genre may also replace one
/// of the foundation's by giving its own the same number (the game then uses the genre's). Refused:
/// two of one owner with one number, two genres with one number, a foundation one at 100 or above, a
/// genre one under 100 that replaces nothing, a `then` that is not a status, no status 0.
fn status_table(all: Vec<(String, i64, serde_json::Value)>, listed: &[String]) {
    let keyed: Vec<(String, i64, String)> = all.iter()
        .map(|(o, _, v)| (o.clone(), v["status"].as_i64().unwrap_or(-1), v["name"].as_str().unwrap_or("").to_string()))
        .collect();
    let chosen = crate::status_rules::choose(&keyed, listed).unwrap_or_else(|why| panic!("{why}"));
    let mut src = String::from("// @generated by build.rs from shared/content/*/status.json (tools/bake_content.gd) - do not edit.
        /// Every status this game has, by number (a genre's replacing the foundation's of the same number).
        pub const STATUSES: &[StatusSeed] = &[
");
    for (n, i) in &chosen {
        let (owner, _, v) = &all[*i];
        let then_id = v["then"].as_i64().unwrap_or(-1);
        let then = if then_id < 0 { 0 } else {
            let t = all.iter().find(|(_, id, _)| *id == then_id).unwrap_or_else(|| panic!(
                "{owner}'s status {n} becomes content {then_id} when it ends, which is not a status"));
            t.2["status"].as_i64().unwrap_or(0) as u8
        };
        let f = |k: &str| v[k].as_f64().unwrap_or_else(|| panic!("{owner}'s status {n} has no {k}: bake again"));
        let b = |k: &str| v[k].as_bool().unwrap_or_else(|| panic!("{owner}'s status {n} has no {k}: bake again"));
        src.push_str(&format!(
            "    StatusSeed {{ status: {n}, name: {:?}, lasts_ms: {}, then: {then}, speed: {:?}f32, burst: {:?}f32, burst_ms: {}, can_sprint: {}, can_jump: {}, can_dash: {}, can_act: {}, targetable: {}, hittable: {} }},
",
            v["name"].as_str().unwrap_or(""), f("lasts_ms") as u32, f("speed") as f32, f("burst") as f32, f("burst_ms") as u32,
            b("can_sprint"), b("can_jump"), b("can_dash"), b("can_act"), b("targetable"),
            v["hittable"].as_bool().unwrap_or(true)));
    }
    src.push_str("];
");
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("statuses.rs"), src).unwrap();
}

/// The holds (DECISIONS #209) -> $OUT_DIR/holds.rs: `HOLDS`, in the order a press is matched (a genre's
/// before the foundation's, which they replace for the presses they share). A hold's status links
/// (`when`, `then`) are content ids, written as the status NUMBER they are (a genre's status replacing
/// the foundation's of that number is the one used). Refused: a press two holds could start (within one
/// owner, or two genres), a hold done to nothing, a status link that is not a status, no seconds.
fn hold_table(holds: &[(String, serde_json::Value)], statuses: &[(String, i64, serde_json::Value)], listed: &[String]) {
    let status_number = |owner: &str, name: &str, field: &str, id: i64| -> i16 {
        if id < 0 {
            return -1;
        }
        let s = statuses.iter().find(|(_, sid, _)| *sid == id).unwrap_or_else(|| panic!(
            "{owner}'s hold '{name}' links {field} to content {id}, which is not a status"));
        s.2["status"].as_i64().unwrap_or(0) as i16
    };
    let kinds = |v: &serde_json::Value| -> Vec<u8> {
        v.as_array().cloned().unwrap_or_default().iter().filter_map(|k| k.as_u64()).map(|k| k as u8).collect()
    };
    let keys: Vec<crate::hold_rules::HoldKey> = holds.iter().map(|(owner, h)| {
        let name = h["name"].as_str().unwrap_or("").to_string();
        let when = status_number(owner, &name, "when", h["when"].as_i64().unwrap_or(-1));
        crate::hold_rules::HoldKey {
            owner: owner.clone(),
            name,
            verb: h["verb"].as_u64().unwrap_or(0) as u8,
            targets: kinds(&h["targets"]),
            doers: kinds(&h["doers"]),
            when: if when < 0 { None } else { Some(when as u8) },
        }
    }).collect();
    let order = crate::hold_rules::choose(&keys, listed).unwrap_or_else(|why| panic!("{why}"));
    let mut src = String::from("// @generated by build.rs from shared/content/*/hold.json (tools/bake_content.gd) - do not edit.
/// Every hold this game has, in the order a press is matched: a genre's before the foundation's.
pub const HOLDS: &[HoldSeed] = &[
");
    for i in order {
        let (owner, h) = &holds[i];
        let k = &keys[i];
        let f = |key: &str| h[key].as_f64().unwrap_or_else(|| panic!("{owner}'s hold '{}' has no {key}: bake again", k.name));
        let b = |key: &str| h[key].as_bool().unwrap_or_else(|| panic!("{owner}'s hold '{}' has no {key}: bake again", k.name));
        let seconds: Vec<f32> = h["seconds_with"].as_array().cloned().unwrap_or_default().iter().filter_map(|s| s.as_f64()).map(|s| s as f32).collect();
        assert!(!seconds.is_empty() && seconds.iter().all(|s| *s > 0.0),
            "{owner}'s hold '{}' needs seconds_with: how long it takes one doer, then two...", k.name);
        let list = |v: &[u8]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(", ");
        src.push_str(&format!(
            "    HoldSeed {{ id: {}, name: {:?}, verb: {}, targets: &[{}], doers: &[{}], when: {}, seconds_with: &[{}], range_m: {:?}f32, max_doers: {}, keeps_progress: {}, stopped_by_damage: {}, stopped_by_moving_m: {:?}f32, then_status: {} }},
",
            h["id"].as_u64().unwrap_or(0), k.name, k.verb, list(&k.targets), list(&k.doers),
            k.when.map(|w| w as i16).unwrap_or(-1),
            seconds.iter().map(|s| format!("{s:?}f32")).collect::<Vec<_>>().join(", "),
            f("range_m") as f32, f("max_doers") as u8, b("keeps_progress"), b("stopped_by_damage"), f("stopped_by_moving_m") as f32,
            status_number(owner, &k.name, "then", h["then"].as_i64().unwrap_or(-1))));
    }
    src.push_str("];
");
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("holds.rs"), src).unwrap();
}

/// WHAT EACH KIND MAY USE (DECISIONS #207) -> $OUT_DIR/kind_abilities.rs: a kind's abilities are every
/// ability its characters list; a kind none of whose characters lists any may use every ability (as
/// before characters listed them). A character listing an ability that is not baked stops the build.
fn kind_ability_table(chars: Vec<(u64, Vec<i64>)>, abilities: &[i64]) {
    let mut kinds: Vec<(u64, Vec<i64>)> = Vec::new();
    for (kind, listed) in chars {
        for a in &listed {
            assert!(*a >= 0 && abilities.contains(a), "a character of kind {kind} lists ability {a}, which is not baked content");
        }
        match kinds.iter_mut().find(|k| k.0 == kind) {
            Some(k) => {
                for a in listed {
                    if !k.1.contains(&a) {
                        k.1.push(a);
                    }
                }
            }
            None => kinds.push((kind, listed)),
        }
    }
    kinds.retain(|k| !k.1.is_empty());
    kinds.sort_by_key(|k| k.0);
    let mut src = String::from("// @generated by build.rs from shared/content (characters' abilities) - do not edit.
        /// Kinds whose characters list abilities, with every ability they list.
        pub const KIND_ABILITIES: &[(u8, &[u32])] = &[
");
    for (kind, mut list) in kinds {
        list.sort();
        src.push_str(&format!("    ({kind}, &[{}]),
", list.iter().map(|a| a.to_string()).collect::<Vec<_>>().join(", ")));
    }
    src.push_str("];
/// Whether an entity of `kind` may use ability `ability_id`: every one, unless its characters list theirs.
        pub fn kind_may_use(kind: u8, ability_id: u32) -> bool {
    KIND_ABILITIES.iter().find(|k| k.0 == kind).map(|k| k.1.contains(&ability_id)).unwrap_or(true)
}
");
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("kind_abilities.rs"), src).unwrap();
}

/// The bodies (DECISIONS #246) -> $OUT_DIR/bodies.rs: `BODIES`, what the module checks of each (who may
/// throw it, how hard, from how far, how many, how long it lasts). Refused: two with one id.
fn body_table(bodies: &[(String, serde_json::Value)]) {
    let mut ids: Vec<u64> = Vec::new();
    let mut src = String::from("// @generated by build.rs from shared/content/*/body.json (tools/bake_content.gd) - do not edit.
/// Every body this game has, by id.
pub const BODIES: &[BodySeed] = &[
");
    for (owner, b) in bodies {
        let id = b["id"].as_u64().unwrap_or_else(|| panic!("{owner} has a body without an id: bake again"));
        assert!(!ids.contains(&id), "two bodies have id {id} (the foundation's and a genre's?): give one another id");
        ids.push(id);
        let name = b["name"].as_str().unwrap_or("");
        let f = |k: &str| b[k].as_f64().unwrap_or_else(|| panic!("{owner}'s body '{name}' has no {k}: bake again"));
        let launchers: Vec<String> = b["launchers"].as_array().cloned().unwrap_or_default().iter()
            .filter_map(|k| k.as_u64()).map(|k| { assert!(k <= 255, "{owner}'s body '{name}' is thrown by kind {k}: kinds are 0-255"); k.to_string() }).collect();
        src.push_str(&format!(
            "    BodySeed {{ id: {id}, name: {name:?}, launchers: &[{}], max_speed: {:?}f32, max_spin: {:?}f32, reach: {:?}f32, max_per_owner: {}, lifetime_s: {:?}f32 }},
",
            launchers.join(", "), f("max_speed_mps") as f32, f("max_spin_rps") as f32, f("reach_m") as f32,
            (f("max_per_owner") as u64).min(255), f("lifetime_s") as f32));
    }
    src.push_str("];
");
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("bodies.rs"), src).unwrap();
}

/// The loot tables (DECISIONS #268) -> $OUT_DIR/loot_tables.rs: `LOOT_TABLES`. Refused: two with one
/// id; a line naming an item or a table this game does not have; a one-of table past 100 %; pity in a
/// one-of table; a table that contains itself or nests past `loot::MAX_DEPTH` (8).
fn loot_table(tables: &[(String, serde_json::Value)], item_ids: &[u64]) {
    let ids: Vec<u64> = tables.iter().map(|(owner, t)| t["id"].as_u64().unwrap_or_else(|| panic!("{owner} has a loot table without an id: bake again"))).collect();
    for (i, id) in ids.iter().enumerate() {
        assert!(!ids[..i].contains(id), "two loot tables have id {id}: give one another id");
    }
    let nested = |t: &serde_json::Value| -> Vec<u64> {
        t["lines"].as_array().cloned().unwrap_or_default().iter().filter_map(|l| l["table"].as_i64()).filter(|&x| x > 0).map(|x| x as u64).collect()
    };
    let mut src = String::from("// @generated by build.rs from shared/content/*/loot_table.json (tools/bake_content.gd) - do not edit.
/// Every loot table this game has, by id.
pub const LOOT_TABLES: &[LootTableSeed] = &[
");
    for (owner, t) in tables {
        let name = t["name"].as_str().unwrap_or("");
        let one_of = t["one_of"].as_bool().unwrap_or(false);
        let mut shares: u64 = 0;
        let mut lines = String::new();
        for (i, l) in t["lines"].as_array().cloned().unwrap_or_default().iter().enumerate() {
            let n = |k: &str| l[k].as_i64().unwrap_or_else(|| panic!("{owner}'s loot table '{name}' line {} has no {k}: bake again", i + 1));
            let (item, table) = (n("item").max(0) as u64, n("table").max(0) as u64);
            assert!((item == 0) != (table == 0), "{owner}'s loot table '{name}' line {}: an item or a table, one", i + 1);
            assert!(item == 0 || item_ids.contains(&item), "{owner}'s loot table '{name}' line {} drops item {item}, which this game does not have", i + 1);
            assert!(table == 0 || ids.contains(&table), "{owner}'s loot table '{name}' line {} rolls table {table}, which this game does not have", i + 1);
            let pity = l["pity"].as_bool().unwrap_or(false);
            assert!(!(pity && one_of), "{owner}'s loot table '{name}' line {}: pity in a one-of table", i + 1);
            let chance = n("chance_pm").clamp(0, 1_000_000) as u64;
            shares += chance;
            lines.push_str(&format!(
                "LootLineSeed {{ item: {item}, table: {table}, chance_pm: {chance}, qty_min: {}, qty_max: {}, to_bag: {}, pity: {pity} }}, ",
                n("qty_min").max(0), n("qty_max").max(n("qty_min")).max(0), l["to_bag"].as_bool().unwrap_or(false)));
        }
        assert!(!one_of || shares <= 1_000_000, "{owner}'s loot table '{name}' is one-of and its shares add up past 100 %");
        let id = t["id"].as_u64().unwrap_or(0);
        // No loops, and no deeper than the roll goes.
        let mut stack: Vec<(u64, u32, Vec<u64>)> = vec![(id, 0, vec![id])];
        while let Some((at, depth, path)) = stack.pop() {
            assert!(depth < 8, "{owner}'s loot table '{name}' nests tables deeper than 8");
            if let Some((_, tt)) = tables.iter().find(|(_, tt)| tt["id"].as_u64() == Some(at)) {
                for next in nested(tt) {
                    assert!(!path.contains(&next), "{owner}'s loot table '{name}' contains itself (through table {next})");
                    let mut p = path.clone();
                    p.push(next);
                    stack.push((next, depth + 1, p));
                }
            }
        }
        src.push_str(&format!("    LootTableSeed {{ id: {id}, name: {name:?}, one_of: {one_of}, lines: &[{lines}] }},
"));
    }
    src.push_str("];
");
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("loot_tables.rs"), src).unwrap();
}

/// The resources (DECISIONS #270) -> $OUT_DIR/resources.rs: `RESOURCES`. Refused: two with one id, a
/// pool that holds nothing, a rate that is not a number.
fn resource_table(resources: &[(String, serde_json::Value)]) {
    let mut ids: Vec<u64> = Vec::new();
    let mut src = String::from("// @generated by build.rs from shared/content/*/resource.json (tools/bake_content.gd) - do not edit.
/// Every resource this game has, by id.
pub const RESOURCES: &[ResourceSeed] = &[
");
    for (owner, r) in resources {
        let id = r["id"].as_u64().unwrap_or_else(|| panic!("{owner} has a resource without an id: bake again"));
        assert!(!ids.contains(&id), "two resources have id {id}: give one another id");
        ids.push(id);
        let key = r["key"].as_str().unwrap_or("");
        let f = |k: &str| r[k].as_f64().unwrap_or_else(|| panic!("{owner}'s resource '{key}' has no {k}: bake again"));
        assert!(f("max") > 0.0, "{owner}'s resource '{key}' holds nothing");
        src.push_str(&format!("    ResourceSeed {{ id: {id}, key: {key:?}, max: {:?}f32, regen_in: {:?}f32, regen_out: {:?}f32, combat_s: {:?}f32 }},
",
            f("max") as f32, f("regen_in").max(0.0) as f32, f("regen_out").max(0.0) as f32, f("combat_s").max(0.0) as f32));
    }
    src.push_str("];
");
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("resources.rs"), src).unwrap();
}

/// The traits (DECISIONS #275) -> $OUT_DIR/traits.rs: `TRAITS`. Refused: two with one id, a trait with no
/// key, an atom with no `what`.
fn trait_table(traits: &[(String, serde_json::Value)]) {
    let mut ids: Vec<u64> = Vec::new();
    let mut src = String::from("// @generated by build.rs from shared/content/*/trait.json (tools/bake_content.gd) - do not edit.
/// Every trait this game has, by id.
pub const TRAITS: &[TraitSeed] = &[
");
    for (owner, t) in traits {
        let id = t["id"].as_u64().unwrap_or_else(|| panic!("{owner} has a trait without an id: bake again"));
        assert!(!ids.contains(&id), "two traits have id {id}: give one another id");
        ids.push(id);
        let key = t["key"].as_str().unwrap_or("");
        assert!(!key.is_empty(), "{owner}'s trait {id} has no key: bake again");
        let tags: Vec<String> = t["applies_to"].as_array().cloned().unwrap_or_default().iter()
            .map(|v| format!("{:?}", v.as_str().unwrap_or(""))).collect();
        let mut atoms = String::new();
        for a in t["atoms"].as_array().cloned().unwrap_or_default() {
            let st = |k: &str| a[k].as_str().unwrap_or("").to_string();
            let f = |k: &str| a[k].as_f64().unwrap_or_else(|| panic!("{owner}'s trait '{key}' has an atom with no {k}: bake again"));
            assert!(!st("what").is_empty(), "{owner}'s trait '{key}' has an atom with no `what`");
            atoms.push_str(&format!("Atom {{ what: {:?}, on: {:?}, mult: {:?}f32, value: {:?}f32, condition: {:?}, threshold_pct: {:?}f32, against: {:?}, cost: {} }}, ",
                st("what"), st("on"), f("mult") as f32, f("value") as f32, st("condition"), f("threshold_pct") as f32, st("against"),
                a["cost"].as_bool().unwrap_or(false)));
        }
        src.push_str(&format!("    TraitSeed {{ id: {id}, key: {key:?}, name: {:?}, applies_to: &[{}], rollable: {}, atoms: &[{atoms}] }},
",
            t["name"].as_str().unwrap_or(""), tags.join(", "), t["rollable"].as_bool().unwrap_or(true)));
    }
    src.push_str("];
");
    fs::write(PathBuf::from(env::var("OUT_DIR").unwrap()).join("traits.rs"), src).unwrap();
}
