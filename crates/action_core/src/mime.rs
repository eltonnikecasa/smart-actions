use mime_guess::from_path;

#[derive(Debug)]
pub enum FileKind {
    Image,
    Video,
    Audio,
    Pdf,
    Archive,
    Unknown,
}

pub fn detect_mime(path: &str) -> String {
    from_path(path)
        .first_or_octet_stream()
        .essence_str()
        .to_string()
}

pub fn detect_kind(path: &str) -> FileKind {
    let mime = detect_mime(path);

    if mime.starts_with("image/") {
        FileKind::Image
    } else if mime.starts_with("video/") {
        FileKind::Video
    } else if mime.starts_with("audio/") {
        FileKind::Audio
    } else if mime == "application/pdf" {
        FileKind::Pdf
    } else if mime.contains("zip")
        || mime.contains("tar")
        || mime.contains("7z")
    {
        FileKind::Archive
    } else {
        FileKind::Unknown
    }
}
