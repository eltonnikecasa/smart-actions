use mime_guess;

#[derive(Debug)]
pub enum FileKind {
    Video,
    Image,
    Audio,
    Pdf,
    Other,
}

pub fn detect_mime(file: &str) -> String {
    mime_guess::from_path(file)
    .first_or_octet_stream()
    .to_string()
}

pub fn detect_kind(file: &str) -> FileKind {
    let mime = detect_mime(file);

    if mime.starts_with("video/") {
        FileKind::Video
    } else if mime.starts_with("image/") {
        FileKind::Image
    } else if mime.starts_with("audio/") {
        FileKind::Audio
    } else if mime == "application/pdf" {
        FileKind::Pdf
    } else {
        FileKind::Other
    }
}
