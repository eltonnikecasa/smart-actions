use serde::Deserialize;

use std::fs;
use std::path::Path;

#[derive(Debug, Deserialize, Clone)]
pub struct MenuConfig {
    pub group: String,
    pub priority: u32,
}

#[derive(Debug, Deserialize, Clone)]
pub struct OutputConfig {

    pub extension: String,

    pub suffix: String,

    pub preserve_extension: bool,
}

#[derive(Debug, Deserialize, Clone)]
pub struct CommandConfig {
    pub args: Vec<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Preset {

    pub id: String,

    pub enabled: bool,

    pub display_name: Option<String>,

    pub min_files: usize,

    pub max_files: usize,

    pub engine: String,

    pub menu: MenuConfig,

    pub mime: Vec<String>,

    pub output: OutputConfig,

    pub command: CommandConfig,
}

pub fn load_preset(
    path: &Path,
) -> Result<Preset, String> {

    let content =
        fs::read_to_string(path)
            .map_err(|e| e.to_string())?;

    let preset: Preset =
        serde_yaml::from_str(&content)
            .map_err(|e| e.to_string())?;

    Ok(preset)
}
