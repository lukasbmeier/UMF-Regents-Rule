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
