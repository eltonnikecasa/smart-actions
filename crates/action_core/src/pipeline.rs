use std::path::Path;

use std::process::{Command, Stdio};
use std::io::{BufRead, BufReader};

use crate::preset::Preset;

use crate::presets::load_all_presets;

pub fn execute_pipeline(
    preset: &Preset,
    inputs: &Vec<String>,
    output: &str,
) {

    if inputs.is_empty() {

        panic!(
            "No input files"
        );
    }

    println!(
        "Executing engine: {}",
        preset.engine
    );

    let status = match preset.engine.as_str() {

        "ffmpeg" => {

            let mut cmd =
                Command::new("ffmpeg");

            for input in inputs {

                cmd.arg("-i");

                cmd.arg(input);
            }

            for arg in &preset.command.args {

                cmd.arg(arg);
            }

            cmd.arg(output);

            if std::env::var_os("SMART_ACTIONS_PROGRESS").is_some() {
                return execute_ffmpeg(cmd, preset, inputs);
            }

            cmd.status()
                .unwrap_or_else(|error| {
                    if error.kind() == std::io::ErrorKind::NotFound {
                        panic!("Dependência necessária não encontrada: ffmpeg");
                    }
                    panic!("Falha ao executar ffmpeg: {error}");
                })
        }

        "img2pdf" => {

            let mut cmd =
                Command::new("img2pdf");

            for input in inputs {

                cmd.arg(input);
            }

            cmd.arg("-o");

            cmd.arg(output);

            cmd.status()
                .unwrap_or_else(|error| {
                    if error.kind() == std::io::ErrorKind::NotFound {
                        panic!("Dependência necessária não encontrada: img2pdf");
                    }
                    panic!("Falha ao executar img2pdf: {error}");
                })
        }

        "qpdf" => {

            let mut cmd =
            Command::new("qpdf");

            for arg in &preset.command.args {

                cmd.arg(arg);
            }

            for input in inputs {

                cmd.arg(input);
            }

            cmd.arg("--");

            cmd.arg(output);

            cmd.status()
            .unwrap_or_else(|error| {
                    if error.kind() == std::io::ErrorKind::NotFound {
                        panic!("Dependência necessária não encontrada: qpdf");
                    }
                    panic!("Falha ao executar qpdf: {error}");
                })
        }

        "ghostscript" => {

            let mut cmd =
                Command::new("gs");

            for arg in &preset.command.args {

                let value =
                    arg.replace(
                        "{output}",
                        output
                    );

                cmd.arg(value);
            }

            for input in inputs {

                cmd.arg(input);
            }

            cmd.status()
                .unwrap_or_else(|error| {
                    if error.kind() == std::io::ErrorKind::NotFound {
                        panic!("Dependência necessária não encontrada: gs");
                    }
                    panic!("Falha ao executar ghostscript: {error}");
                })
        }

        _ => {

            panic!(
                "Unknown engine: {}",
                preset.engine
            );
        }
    };

    println!(
        "Engine exit status: {:?}",
        status
    );

    if !status.success() {

        panic!(
            "Pipeline execution failed"
        );
    }
}

pub fn run_action(
    presets_dir: &str,
    action_id: &str,
    inputs: &Vec<String>,
    output: &str,
) {

    let presets =
        load_all_presets(
            presets_dir
        );

    let preset =
        presets
            .into_iter()
            .find(
                |p| p.id == action_id
            )
            .unwrap_or_else(|| {

                panic!(
                    "Preset not found: {}",
                    action_id
                )
            });

    for input in inputs {

        let input_path =
            Path::new(input);

        if !input_path.exists() {

            panic!(
                "Input file does not exist: {}",
                input
            );
        }
    }

    execute_pipeline(
        &preset,
        inputs,
        output,
    );
}

// Progress is opt-in for the launcher; normal CLI output stays unchanged.
fn execute_ffmpeg(mut cmd: Command, preset: &Preset, inputs: &[String]) {
    let duration = if preset.menu.group != "image" && inputs.len() == 1 {
        Command::new("ffprobe")
            .args(["-v", "error", "-show_entries", "format=duration",
                   "-of", "default=noprint_wrappers=1:nokey=1", "-i"])
            .arg(&inputs[0])
            .output().ok()
            .filter(|output| output.status.success())
            .and_then(|output| String::from_utf8(output.stdout).ok())
            .and_then(|duration| duration.trim().parse::<f64>().ok())
            .filter(|duration| duration.is_finite() && *duration > 0.0)
    } else {
        None
    };
    // These global flags only control reporting, not the encoded output.
    cmd.args(["-progress", "pipe:1", "-nostats"]);
    let mut child = cmd.stdout(Stdio::piped()).spawn()
        .unwrap_or_else(|error| panic!("Falha ao executar ffmpeg: {error}"));
    let mut previous = None;
    let mut read_error = None;
    for line in BufReader::new(child.stdout.take().unwrap()).lines() {
        match line {
            Ok(line) => {
                if let Some(value) = progress_percent(&line, duration) {
                    if previous.is_none_or(|old| value > old) {
                        println!("SMART_ACTIONS_PROGRESS={value}");
                        previous = Some(value);
                    }
                }
            }
            Err(error) => { read_error = Some(error); break; }
        }
    }
    if read_error.is_some() {
        let _ = child.kill();
    }
    let status = child.wait().expect("Falha ao aguardar ffmpeg");
    if let Some(error) = read_error { panic!("Falha ao ler progresso: {error}"); }
    assert!(status.success(), "Pipeline execution failed: {status}");
}

fn progress_percent(line: &str, duration: Option<f64>) -> Option<u32> {
    let duration = duration.filter(|value| value.is_finite() && *value > 0.0)?;
    let position = line.strip_prefix("out_time_us=")?.parse::<u64>().ok()?;
    // 100 is reserved for successful process termination, not progress=end.
    Some(((position as f64 / 1_000_000.0 / duration * 100.0) as u32).min(99))
}

#[cfg(test)]
mod progress_tests {
    use super::progress_percent;

    #[test]
    fn percentages_require_duration_and_position() {
        assert_eq!(progress_percent("out_time_us=2500000", Some(10.0)), Some(25));
        assert_eq!(progress_percent("out_time_us=10000000", Some(10.0)), Some(99));
        for duration in [None, Some(0.0), Some(f64::NAN), Some(-1.0)] {
            assert_eq!(progress_percent("out_time_us=1", duration), None);
        }
        for line in ["out_time_us=N/A", "out_time_us=-1", "progress=end"] {
            assert_eq!(progress_percent(line, Some(10.0)), None);
        }
    }
}
