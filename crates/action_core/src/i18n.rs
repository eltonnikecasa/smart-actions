use serde::Deserialize;

use std::collections::HashMap;
use std::fs;

#[derive(Debug, Deserialize)]
pub struct Language {
    pub app_name: String,

    pub messages: HashMap<String, String>,

    pub actions: HashMap<String, String>,
}

pub fn load_language(locale: &str) -> Result<Language, String> {
    let path = format!("lang/{}.yaml", locale);

    let content = fs::read_to_string(path)
        .map_err(|e| e.to_string())?;

    let lang: Language =
        serde_yaml::from_str(&content)
            .map_err(|e| e.to_string())?;

    Ok(lang)
}
