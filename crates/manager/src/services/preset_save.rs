use std::fs;

use crate::models::category::FileCategory;

// Create filesystem-safe IDs.
//
// Custom presets receive a prefix
// to separate them from bundled presets.
pub fn generate_id(
    name: &str
) -> String {

    format!(
        "custom_{}",
        name
            .to_lowercase()
            .replace(" ", "_")
            .replace("-", "_")
    )
}

// Minimal alpha persistence.
//
// Goal:
// - valid schema
// - visible in UI
// - usable for testing
pub fn save_preset(

    display_name: &str,

    enabled: bool,

    multi_file: bool,

    category: &FileCategory,

    arguments: &str,

    output_format: &str,
) {

    let id =
        generate_id(
            display_name
        );

    let Some(dir) = dirs::config_dir().map(|path| path.join("smart-actions/presets/custom")) else {
        return;
    };

    let _ = fs::create_dir_all(&dir);

    let path =
        dir.join(
            format!(
                "{}.yaml",
                id
            )
        );

    let (
        min_files,
        max_files
    ) = if multi_file {

        (
            2,
            999
        )

    } else {

        (
            1,
            1
        )
    };

    // Convert CLI string
    // into YAML argument list.
    let args_lines =
        arguments
            .split_whitespace()
            .map(
                |arg| {

                format!(
                    "    - {}",
                    arg
                )
            })
            .collect::<Vec<_>>()
            .join("\n");

    let yaml =
        format!(
r#"id: {}

enabled: {}

min_files: {}

max_files: {}

multi_file: {}

engine: {}

menu:
  group: custom
  priority: 99

mime:
  - {}

output:
  extension: {}
  preserve_extension: false
  suffix: converted

command:
  args:
{}
"#,
            id,
            enabled,
            min_files,
            max_files,
            multi_file,
            category
                .default_engine(),
            category.mime(),
            output_format,
            args_lines,
        );

    let _ =
        fs::write(
            path,
            yaml
        );
}

// Delete only custom presets.
//
// Built-in presets remain protected.
pub fn delete_preset(
    preset_id: &str
) {

    if !preset_id.starts_with(
        "custom_"
    ) {

        return;
    }

    let Some(config_dir) = dirs::config_dir() else { return; };
    let path = config_dir
        .join("smart-actions/presets/custom")
        .join(format!("{}.yaml", preset_id));

    let _ =
        fs::remove_file(
            path
        );
}
