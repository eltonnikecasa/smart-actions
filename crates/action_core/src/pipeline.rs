use std::path::Path;

use std::process::Command;

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

            cmd.status()
                .expect(
                    "Failed to execute ffmpeg"
                )
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
                .expect(
                    "Failed to execute img2pdf"
                )
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
            .expect(
                "Failed to execute qpdf"
            )
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
                .expect(
                    "Failed to execute ghostscript"
                )
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
