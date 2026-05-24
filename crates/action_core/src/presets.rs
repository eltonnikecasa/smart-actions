use std::fs;
use std::path::Path;

use crate::preset::{
    load_preset,
    Preset,
};

pub fn load_all_presets(
    presets_dir: &str,
) -> Vec<Preset> {

    let mut presets = Vec::new();

    visit_dirs(
        Path::new(presets_dir),
        &mut presets,
    );

    presets
}

fn visit_dirs(
    dir: &Path,
    presets: &mut Vec<Preset>,
) {

    if !dir.is_dir() {
        return;
    }

    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(_) => return,
    };

    for entry in entries {

        let entry = match entry {
            Ok(e) => e,
            Err(_) => continue,
        };

        let path = entry.path();

        if path.is_dir() {

            visit_dirs(&path, presets);

        } else if let Some(ext) =
            path.extension() {

            if ext == "yaml" {

                match load_preset(&path) {

                    Ok(preset) => {

                        if preset.enabled {
                            presets.push(preset);
                        }
                    }

                    Err(err) => {
                        println!(
                            "Failed to load preset {:?}: {}",
                            path,
                            err
                        );
                    }
                }
            }
        }
    }
}

pub fn find_preset_by_id(
    presets_dir: &str,
    preset_id: &str,
) -> Option<Preset> {

    let presets =
        load_all_presets(presets_dir);

    for preset in presets {

        if preset.id == preset_id {
            return Some(preset);
        }
    }

    None
}
