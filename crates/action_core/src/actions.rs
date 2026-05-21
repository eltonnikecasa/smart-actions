use crate::mime::FileKind;

#[derive(Debug)]
pub struct Action {
    pub id: &'static str,
    pub name: &'static str,
}

pub fn actions_for_kind(kind: &FileKind) -> Vec<Action> {
    match kind {
        FileKind::Video => vec![
            Action {
                id: "resolve_safe",
                name: "Prepare for Resolve",
            },
            Action {
                id: "proxy",
                name: "Generate Proxy",
            },
            Action {
                id: "extract_audio",
                name: "Extract Audio",
            },
        ],

        FileKind::Image => vec![
            Action {
                id: "to_webp",
                name: "Convert to WebP",
            },
            Action {
                id: "resize",
                name: "Resize Image",
            },
        ],

        FileKind::Audio => vec![
            Action {
                id: "to_wav",
                name: "Convert to WAV",
            },
        ],

        FileKind::Pdf => vec![
            Action {
                id: "compress_pdf",
                name: "Compress PDF",
            },
        ],

        _ => vec![],
    }
}
