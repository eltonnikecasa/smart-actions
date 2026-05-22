use serde::Deserialize;
use std::fs;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub locale: String,
    pub presets_dir: String,
    pub default_output_dir: String,
    pub log_level: Option<String>,
}

pub fn load_config() -> Result<Config, String> {
    let path = dirs::config_dir()
        .ok_or("No config dir found")?
        .join("smart-actions/config.yaml");

    let content = fs::read_to_string(path)
        .map_err(|e| e.to_string())?;

    let config: Config =
        serde_yaml::from_str(&content)
            .map_err(|e| e.to_string())?;

    Ok(config)
}
