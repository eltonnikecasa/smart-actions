use std::path::Path;
use std::process::Command;

use crate::config::load_config;
use crate::i18n::load_language;
use crate::presets::load_preset;

pub fn run_action(action_id: &str, file: &str) {
    let config = load_config()
        .expect("Failed to load config");

    let lang = load_language(&config.locale)
        .expect("Failed to load language");

    println!(
        "{}: {}",
        lang.messages["running_action"],
        action_id
    );

    println!(
        "{}: {}",
        lang.messages["input_file"],
        file
    );

    match action_id {
        "resolve_safe" => {
            run_preset(
                &format!(
                    "{}/resolve/resolve-safe.yaml",
                    config.presets_dir
                ),
                file,
                &lang,
            );
        }

        _ => {
            println!("Unknown action: {}", action_id);
        }
    }
}

fn output_path(
    file: &str,
    suffix: &str,
    new_extension: &str,
) -> String {
    let path = Path::new(file);

    let parent = path.parent()
        .unwrap_or(Path::new("."));

    let stem = path
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy();

    let original_extension = path
        .extension()
        .unwrap_or_default()
        .to_string_lossy();

    let filename = if original_extension == new_extension {
        format!("{}_{}.{}", stem, suffix, new_extension)
    } else {
        format!("{}.{}", stem, new_extension)
    };

    parent
        .join(filename)
        .to_string_lossy()
        .to_string()
}

fn run_preset(
    preset_path: &str,
    file: &str,
    lang: &crate::i18n::Language,
) {
    let preset = match load_preset(preset_path) {
        Ok(preset) => preset,

        Err(e) => {
            println!("Failed to load preset: {}", e);
            return;
        }
    };

    println!("Loaded preset: {}", preset.id);

    let output = output_path(
        file,
        &preset.id,
        &preset.extension,
    );

    println!("Output: {}", output);

    let mut cmd = Command::new("ffmpeg");

    cmd.arg("-y");

    cmd.arg("-i").arg(file);

    for arg in &preset.ffmpeg.args {
        cmd.arg(arg);
    }

    cmd.arg(&output);

    println!("Executing ffmpeg...");

    match cmd.status() {
        Ok(status) => {
            println!("FFmpeg exit status: {}", status);

            if status.success() {
                println!(
                    "{}",
                    lang.messages["conversion_completed"]
                );
            } else {
                println!(
                    "{}",
                    lang.messages["ffmpeg_error"]
                );
            }
        }

        Err(e) => {
            println!(
                "{}: {}",
                lang.messages["ffmpeg_not_found"],
                e
            );
        }
    }
}
