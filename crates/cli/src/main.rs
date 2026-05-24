use clap::{Parser, Subcommand};

use smart_actions_core::mime::{
    detect_kind,
    detect_mime,
};

use smart_actions_core::pipeline::run_action;

use smart_actions_core::kde::{
    generate_kde_menu,
};

use smart_actions_core::config::load_config;

use smart_actions_core::presets::load_all_presets;

#[derive(Parser)]
#[command(name = "smart-actions")]
#[command(version = "0.1.0")]
#[command(about = "Context-aware file actions for Linux")]
struct Cli {

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {

    Mime {
        file: String,
    },

    Invoke {
        action: String,

        files: Vec<String>,
    },

    GenerateKdeMenu,
}

fn main() {

    let cli = Cli::parse();

    match cli.command {

        Commands::Mime { file } => {

            let mime =
                detect_mime(&file);

            let kind =
                detect_kind(&file);

            println!("MIME: {}", mime);

            println!("Kind: {:?}", kind);
        }

        Commands::Invoke {
            action,
            files,
        } => {

            if files.is_empty() {

                panic!(
                    "No input files"
                );
            }

            let config =
                load_config()
                    .expect(
                        "Failed to load config"
                    );

            let presets =
                load_all_presets(
                    &config.presets_dir
                );

            let preset =
                presets
                    .iter()
                    .find(
                        |p| p.id == action
                    )
                    .expect(
                        "Preset not found"
                    );

            let first_file =
                &files[0];

            let input_path =
                std::path::Path::new(
                    first_file
                );

            let stem =
                input_path
                    .file_stem()
                    .unwrap()
                    .to_string_lossy();

            let parent =
                input_path
                    .parent()
                    .unwrap();

                    let extension = if
                    preset.output.preserve_extension {

                        input_path
                        .extension()
                        .unwrap()
                        .to_string_lossy()
                        .to_string()

                    } else {

                        preset.output
                        .extension
                        .clone()
                    };

                    let mut counter = 0;

                    let output = loop {

                        let filename = if counter == 0 {

                            format!(
                                "{}_{}.{}",
                                stem,
                                preset.output.suffix,
                                extension
                            )

                        } else {

                            format!(
                                "{}_{}({}).{}",
                                    stem,
                                    preset.output.suffix,
                                    counter,
                                    extension
                            )
                        };

                        let candidate =
                        parent.join(filename);

                        if !candidate.exists() {

                            break candidate;
                        }

                        counter += 1;
                    };

            run_action(
                &config.presets_dir,
                &action,
                &files,
                output.to_str().unwrap(),
            );
        }

        Commands::GenerateKdeMenu => {

            generate_kde_menu();
        }
    }
}
