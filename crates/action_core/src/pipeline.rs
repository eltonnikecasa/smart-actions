use std::process::{Command, Stdio};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::thread;
use std::io::{BufRead, BufReader};

use crate::config::load_config;
use crate::i18n::load_language;
use crate::presets::load_preset;
use crate::output::build_output_path;

pub fn run_action(action_id: &str, file: &str) {
    let config = load_config()
    .expect("Failed to load config");

    let lang = load_language(&config.locale)
    .expect("Failed to load language");

    println!("{}: {}", lang.messages["running_action"], action_id);
    println!("{}: {}", lang.messages["input_file"], file);

    match action_id {
        "resolve_safe" => {
            run_preset(
                "videos",
                &format!("{}/resolve/resolve-safe.yaml", config.presets_dir),
                       action_id,
                       file,
                       &lang,
            );
        }

        _ => {
            println!("Unknown action");
        }
    }
}

fn run_preset(
    category: &str,
    preset_path: &str,
    action_id: &str,
    file: &str,
    lang: &crate::i18n::Language,
) {
    let preset = match load_preset(preset_path) {
        Ok(p) => p,
        Err(e) => {
            println!("Failed to load preset: {}", e);
            return;
        }
    };

    println!("Loaded preset: {}", preset.id);

    let output = build_output_path(file, action_id, &preset.extension);

    println!("Output: {}", output);

    let mut cmd = Command::new("ffmpeg");

    cmd.arg("-y")
    .arg("-i")
    .arg(file);

    for arg in &preset.ffmpeg.args {
        cmd.arg(arg);
    }

    cmd.arg(&output);

    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let cancel_flag = Arc::new(AtomicBool::new(false));
    let cancel_flag_ui = cancel_flag.clone();

    // UI thread simples (terminal fallback por enquanto)
    thread::spawn(move || {
        println!("[SmartActions] Running... Press ENTER to cancel");
        let mut input = String::new();
        std::io::stdin().read_line(&mut input).ok();
        cancel_flag_ui.store(true, Ordering::SeqCst);
    });

    match cmd.spawn() {
        Ok(mut child) => {
            let stderr = child.stderr.take().unwrap();
            let reader = BufReader::new(stderr);

            for line in reader.lines() {
                if cancel_flag.load(Ordering::SeqCst) {
                    let _ = child.kill();
                    println!("Cancelled.");
                    return;
                }

                if let Ok(l) = line {
                    if l.contains("time=") {
                        println!("{}", l);
                    }
                }
            }

            match child.wait() {
                Ok(status) if status.success() => {
                    println!("{}", lang.messages["conversion_completed"]);
                }

                Ok(_) => {
                    println!("{}", lang.messages["ffmpeg_error"]);
                }

                Err(_) => {
                    println!("{}", lang.messages["ffmpeg_not_found"]);
                }
            }
        }

        Err(_) => {
            println!("{}", lang.messages["ffmpeg_not_found"]);
        }
    }
}
