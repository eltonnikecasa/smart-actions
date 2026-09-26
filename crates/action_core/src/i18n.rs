use std::collections::HashMap;

use serde::Deserialize;

// Language structure.
//
// actions:
//   preset translations
//
// ui:
//   interface translations
//
// messages:
//   runtime messages/errors
#[derive(
    Debug,
    Deserialize,
    Clone,
)]
pub struct Language {

    pub app_name: String,

    #[serde(default)]
    pub messages:
        HashMap<String, String>,

    #[serde(default)]
    pub actions:
        HashMap<String, String>,

    #[serde(default)]
    pub ui:
        HashMap<String, String>,
}

pub fn load_language(
    locale: &str,
) -> Result<
    Language,
    Box<dyn std::error::Error>
> {

    let installed_path = dirs::data_dir()
        .map(|data| data.join("smart-actions/share/lang").join(format!("{}.yaml", locale)));
    let path = installed_path
        .filter(|path| path.is_file())
        .unwrap_or_else(|| std::path::PathBuf::from(format!("lang/{}.yaml", locale)));

    let content =
        std::fs::read_to_string(
            path
        )?;

    let lang =
        serde_yaml::from_str(
            &content
        )?;

    Ok(lang)
}
