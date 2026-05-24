// High-level categories keep the UI simple.
//
// Users think in media types,
// not MIME types or engines.
#[derive(
    PartialEq,
    Clone,
)]
pub enum FileCategory {

    Image,

    Audio,

    Video,

    Pdf,
}

impl FileCategory {

    pub fn label(
        &self
    ) -> &'static str {

        match self {

            Self::Image => "image",

            Self::Audio => "audio",

            Self::Video => "video",

            Self::Pdf => "pdf",
        }
    }

    // MIME is automatic.
    // Users should rarely edit this manually.
    pub fn mime(
        &self
    ) -> &'static str {

        match self {

            Self::Image => "image/*",

            Self::Audio => "audio/*",

            Self::Video => "video/*",

            Self::Pdf => "application/pdf",
        }
    }

    // Engines are auto-selected
    // from category defaults.
    pub fn default_engine(
        &self
    ) -> &'static str {

        match self {

            Self::Image =>
                "imagemagick",

            Self::Audio =>
                "ffmpeg",

            Self::Video =>
                "ffmpeg",

            Self::Pdf =>
                "ghostscript",
        }
    }

    // Contextual formats reduce
    // invalid combinations.
    pub fn formats(
        &self
    ) -> Vec<&'static str> {

        match self {

            Self::Image => vec![
                "png",
                "jpg",
                "webp",
            ],

            Self::Audio => vec![
                "mp3",
                "wav",
                "flac",
            ],

            Self::Video => vec![
                "mp4",
                "mkv",
                "webm",
            ],

            Self::Pdf => vec![
                "pdf",
            ],
        }
    }

    // Presets help users understand
    // how CLI arguments work.
    pub fn argument_presets(
        &self
    ) -> Vec<&'static str> {

        match self {

            Self::Image => vec![
                "-quality 85",
                "-resize 1920x1080",
                "-strip",
            ],

            Self::Audio => vec![
                "-b:a 192k",
                "loudnorm",
                "acompressor",
            ],

            Self::Video => vec![
                "-crf 23",
                "-crf 28",
                "-preset slow",
            ],

            Self::Pdf => vec![
                "-dPDFSETTINGS=/ebook",
                "-dPDFSETTINGS=/screen",
            ],
        }
    }
}
