// THE BAKED CONTENT (docs/CONTENT_TOOLING_SPEC.md §1.2, DECISIONS #199). Content is edited as
// `.tres` resources in Godot (`foundation/content/`, `game/<genre>/content/`) and baked by
// `tools/bake_content.gd` to `shared/content/<owner>/<type>.json`, with a manifest of hashes. This
// step refuses to build while the bake is stale, naming the file: a `.tres` changed or added since
// the bake, or a baked file edited by hand. Then it compiles what the module seeds:
//
//   shared/content/<owner>/ability.json -> $OUT_DIR/content.rs (`ABILITIES`, seeded at init)
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
        if info["type"] == "ability" {
            for it in doc["items"].as_array().cloned().unwrap_or_default() {
                let id = it["ability_id"].as_u64().expect("an ability without an ability_id");
                let f = |k: &str| it[k].as_f64().unwrap_or_else(|| panic!("{out}: ability {id} has no {k}"));
                let data = serde_json::json!({ "name": it["name"].as_str().unwrap_or("") }).to_string();
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
