use crate::mime::FileKind;

pub fn resolve_action(file: &str) -> Option<&'static str> {
    let kind = crate::mime::detect_kind(file);

    match kind {
        FileKind::Video => Some("resolve_safe"),
        FileKind::Image => Some("image_convert"),
        FileKind::Audio => Some("extract_audio"),
        FileKind::Pdf => Some("pdf_compress"),
        _ => None,
    }
}
