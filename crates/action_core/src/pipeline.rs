use std::path::Path;
use std::process::Command;

pub fn run_action(action_id: &str, file: &str) {
    println!("Running action: {}", action_id);
    println!("Input file: {}", file);

    match action_id {
        "resolve_safe" => {
            run_resolve_safe(file);
        }

        "proxy" => {
            println!("Generating proxy...");
        }

        "extract_audio" => {
            println!("Extracting audio...");
        }

        _ => {
            println!("Unknown action");
        }
    }
}

fn output_path(file: &str, suffix: &str, new_extension: &str) -> String {
    let path = Path::new(file);

    let stem = path
        .file_stem()
        .unwrap_or_default()
        .to_string_lossy();

    let original_extension = path
        .extension()
        .unwrap_or_default()
        .to_string_lossy();

    if original_extension == new_extension {
        format!("{}_{}.{}", stem, suffix, new_extension)
    } else {
        format!("{}.{}", stem, new_extension)
    }
}

fn run_resolve_safe(file: &str) {
    let output = output_path(file, "resolve", "mov");

    println!("Preparing video for DaVinci Resolve...");
    println!("Output: {}", output);

    let status = Command::new("ffmpeg")
        .arg("-i")
        .arg(file)
        .arg("-c:v")
        .arg("prores_ks")
        .arg("-profile:v")
        .arg("1")
        .arg("-c:a")
        .arg("pcm_s16le")
        .arg(&output)
        .status();

    match status {
        Ok(status) => {
            if status.success() {
                println!("Conversion completed");
            } else {
                println!("FFmpeg exited with error");
            }
        }

        Err(error) => {
            println!("Failed to execute FFmpeg");
            println!("{}", error);
        }
    }
}
