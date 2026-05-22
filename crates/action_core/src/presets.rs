use serde::Deserialize;

use std::fs;

#[derive(Debug, Deserialize)]
pub struct Preset {
    pub id: String,
    pub extension: String,
    pub ffmpeg: FFmpegPreset,
}

#[derive(Debug, Deserialize)]
pub struct FFmpegPreset {
    pub args: Vec<String>,
}

pub fn load_preset(path: &str) -> Result<Preset, String> {
    let content = fs::read_to_string(path)
        .map_err(|e| e.to_string())?;

    let preset: Preset =
        serde_yaml::from_str(&content)
            .map_err(|e| e.to_string())?;

    Ok(preset)
}
