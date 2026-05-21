use clap::{Parser, Subcommand};

use smart_actions_core::actions::actions_for_kind;

use smart_actions_core::mime::{
    detect_kind,
    detect_mime,
};

use smart_actions_core::pipeline::run_action;

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
        file: String,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Mime { file } => {
            let mime = detect_mime(&file);
            let kind = detect_kind(&file);

            println!("MIME: {}", mime);
            println!("Kind: {:?}\n", kind);

            let actions = actions_for_kind(&kind);

            println!("Available Actions:");

            for action in actions {
                println!("- {} ({})", action.name, action.id);
            }
        }

        Commands::Invoke { action, file } => {
            run_action(&action, &file);
        }
    }
}
