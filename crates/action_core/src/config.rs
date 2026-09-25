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

    if !path.exists() {
        let presets = dirs::config_dir()
            .ok_or("No config dir found")?
            .join("smart-actions/presets");
        return Ok(Config {
            locale: "pt_BR".to_string(),
            presets_dir: presets.to_string_lossy().into_owned(),
            default_output_dir: dirs::download_dir()
                .unwrap_or_else(|| dirs::home_dir().unwrap_or_default())
                .to_string_lossy().into_owned(),
            log_level: None,
        });
    }

    let content = fs::read_to_string(path)
        .map_err(|e| e.to_string())?;

    let config: Config =
        serde_yaml::from_str(&content)
            .map_err(|e| e.to_string())?;

    Ok(config)
}
