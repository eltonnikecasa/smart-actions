use serde::Deserialize;

use std::collections::HashMap;
use std::fs;

#[derive(Debug, Deserialize)]
pub struct Language {
    pub app_name: String,

    pub messages: HashMap<String, String>,

    pub actions: HashMap<String, String>,
}

pub fn load_language(
    locale: &str,
) -> Result<Language, String> {

    println!("Locale requested: {}", locale);

    let config_dir = dirs::config_dir()
        .ok_or("No config dir found")?;

    println!("Config dir: {:?}", config_dir);

    let lang_dir = config_dir.join(
        "smart-actions/lang"
    );

    println!("Lang dir: {:?}", lang_dir);

    let path = lang_dir.join(
        format!("{}.yaml", locale)
    );

    println!("Final lang path: {:?}", path);

    let content = fs::read_to_string(&path)
        .map_err(|e| e.to_string())?;

    let lang: Language =
        serde_yaml::from_str(&content)
            .map_err(|e| e.to_string())?;

    Ok(lang)
}
