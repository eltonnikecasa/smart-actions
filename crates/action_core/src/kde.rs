use std::collections::HashMap;
use std::fs;

use crate::config::load_config;
use crate::i18n::load_language;

use crate::presets::load_all_presets;

pub fn generate_kde_menu() {

    let config =
        load_config()
            .expect("Failed to load config");

    let lang =
        load_language(&config.locale)
            .expect("Failed to load language");

    let presets =
        load_all_presets(
            &config.presets_dir
        );

    let mut grouped:
        HashMap<
            (String, bool),
            Vec<_>
        > = HashMap::new();

    for preset in presets {

        let multi_file =
            preset.max_files > 1;

        for mime in &preset.mime {

            grouped
                .entry(
                    (
                        mime.clone(),
                        multi_file
                    )
                )
                .or_default()
                .push(
                    preset.clone()
                );
        }
    }

    for (
        (mime, multi_file),
        presets
    ) in grouped {

        generate_menu_for_mime(
            &mime,
            multi_file,
            presets,
            &lang,
        );
    }
}

fn generate_menu_for_mime(
    mime: &str,
    multi_file: bool,
    presets: Vec<crate::preset::Preset>,
    lang: &crate::i18n::Language,
) {

    let mut desktop =
        String::new();

    let mut actions =
        Vec::new();

    desktop.push_str(
        "[Desktop Entry]\n"
    );

    desktop.push_str(
        "Type=Service\n"
    );

    desktop.push_str(
        "ServiceTypes=KonqPopupMenu/Plugin\n"
    );

    if multi_file {

        desktop.push_str(
            "X-KDE-MinNumberOfUrls=2\n"
        );

    } else {

        desktop.push_str(
            "X-KDE-RequiredNumberOfUrls=1\n"
        );
    }

    desktop.push_str(
        &format!(
            "MimeType={};\n\n",
            mime
        )
    );

    for preset in &presets {

        actions.push(
            preset.id.clone()
        );
    }

    desktop.push_str(
        &format!(
            "Actions={};\n\n",
            actions.join(";")
        )
    );

    desktop.push_str(
        "X-KDE-Submenu=Smart Actions\n"
    );

    desktop.push_str(
        "X-KDE-Priority=TopLevel\n\n"
    );

    for preset in presets {

        let name =
            lang.actions
                .get(&preset.id)
                .cloned()
                .unwrap_or(
                    preset.id.clone()
                );

        desktop.push_str(
            &format!(
                "[Desktop Action {}]\n",
                preset.id
            )
        );

        desktop.push_str(
            &format!(
                "Name={}\n",
                name
            )
        );

        desktop.push_str(
            "Icon=applications-multimedia\n"
        );

        let file_arg = if multi_file {

            "%F"

        } else {

            "%f"
        };

        desktop.push_str(
            &format!(
                "Exec=/home/enc/Documentos/smart-actions/scripts/smart-actions-launcher {} {}\n\n",
                file_arg,
                preset.id
            )
        );
    }

    let safe_name =
        mime
            .replace("/", "-")
            .replace("*", "all");

    let mode = if multi_file {

        "multi"

    } else {

        "single"
    };

    let filename =
        format!(
            "smart-actions-{}-{}.desktop",
            mode,
            safe_name
        );

    let target =
        dirs::home_dir()
            .unwrap()
            .join(
                format!(
                    ".local/share/kio/servicemenus/{}",
                    filename
                )
            );

    fs::write(&target, desktop)
        .expect("Failed to write menu");

    let _ =
        std::process::Command::new(
            "chmod"
        )
        .arg("+x")
        .arg(&target)
        .status();

    println!(
        "Generated KDE menu: {:?}",
        target
    );
}
