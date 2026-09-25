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

    Install,
    Update,
    Check,
    Repair,
    Doctor,
    Version,
    Uninstall,
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

        command @ (Commands::Install | Commands::Update | Commands::Check | Commands::Repair | Commands::Doctor | Commands::Version | Commands::Uninstall) => {
            let action = match command {
                Commands::Install => "install",
                Commands::Update => "update",
                Commands::Check => "check",
                Commands::Repair => "repair",
                Commands::Doctor => "doctor",
                Commands::Version => "version",
                Commands::Uninstall => "uninstall",
                _ => unreachable!(),
            };
            let data_home = std::env::var_os("XDG_DATA_HOME")
                .map(std::path::PathBuf::from)
                .or_else(|| std::env::var_os("HOME").map(|home| std::path::PathBuf::from(home).join(".local/share")))
                .expect("Could not determine user data directory");
            let governor = data_home.join("smart-actions/smart-actions-governor.sh");
            let status = std::process::Command::new("bash")
                .arg(governor)
                .arg(action)
                .status()
                .expect("Could not start Smart Actions Governor");
            if !status.success() {
                std::process::exit(status.code().unwrap_or(1));
            }
        }
    }
}
