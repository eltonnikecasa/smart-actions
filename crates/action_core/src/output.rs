use std::path::Path;

pub fn build_output_path(
    input_file: &str,
    action: &str,
    extension: &str,
) -> String {
    let path = Path::new(input_file);

    let parent = path
    .parent()
    .unwrap_or_else(|| Path::new("."));

    let stem = path
    .file_stem()
    .unwrap_or_default()
    .to_string_lossy();

    format!(
        "{}/{}_{}.{}",
        parent.display(),
            stem,
            action,
            extension
    )
}
