use eframe::egui;

use crate::models::category::FileCategory;

// Editor screen balances:
// - simplicity
// - transparency
// - flexibility
pub fn show_editor_screen(

    ui: &mut egui::Ui,

    tr: &dyn Fn(&str) -> String,

    category: &mut FileCategory,

    output_format: &mut String,

    display_name: &mut String,

    enabled: &mut bool,

    multi_file: &mut bool,

    arguments: &mut String,
) {

    ui.vertical_centered(
        |ui| {

            ui.add_space(10.0);

            ui.heading(
                tr(
                    "preset_editor"
                )
            );

            ui.add_space(15.0);
        }
    );

    ui.separator();

    ui.add_space(20.0);

    ui.group(
        |ui| {

            ui.label(
                tr(
                    "display_name"
                )
            );

            ui.text_edit_singleline(
                display_name
            );

            ui.add_space(15.0);

            ui.label(
                tr(
                    "internal_id"
                )
            );

            ui.monospace(
                display_name
                    .replace(
                        " ",
                        "_"
                    )
                    .to_lowercase()
            );

            ui.add_space(15.0);

            ui.checkbox(
                enabled,
                tr("enabled")
            );

            ui.add_space(10.0);

            ui.checkbox(
                multi_file,
                tr("multi_file")
            );
        }
    );

    ui.add_space(20.0);

    ui.group(
        |ui| {

            ui.label(
                tr(
                    "category"
                )
            );

            ui.add_space(5.0);

            let previous_category =
                category.clone();

            egui::ComboBox::from_id_salt(
                "category"
            )
            .selected_text(
                tr(
                    category.label()
                )
            )
            .show_ui(
                ui,
                |ui| {

                    ui.selectable_value(
                        category,
                        FileCategory::Image,
                        tr("image")
                    );

                    ui.selectable_value(
                        category,
                        FileCategory::Audio,
                        tr("audio")
                    );

                    ui.selectable_value(
                        category,
                        FileCategory::Video,
                        tr("video")
                    );

                    ui.selectable_value(
                        category,
                        FileCategory::Pdf,
                        tr("pdf")
                    );
                }
            );

            // Reset incompatible formats
            // after category changes.
            if previous_category
                != *category {

                *output_format =
                    category
                        .formats()[0]
                        .to_string();

                *arguments =
                    category
                        .argument_presets()[0]
                        .to_string();
            }

            ui.add_space(15.0);

            ui.label(
                tr(
                    "output_format"
                )
            );

            ui.add_space(5.0);

            egui::ComboBox::from_id_salt(
                "output_format"
            )
            .selected_text(
                output_format.as_str()
            )
            .show_ui(
                ui,
                |ui| {

                    for format in
                        category
                            .formats() {

                        ui.selectable_value(
                            output_format,
                            format.to_string(),
                            format
                        );
                    }
                }
            );
        }
    );

    ui.add_space(20.0);

    ui.group(
        |ui| {

            ui.label(
                tr(
                    "technical_info"
                )
            );

            ui.add_space(10.0);

            ui.label(
                format!(
                    "MIME: {}",
                    category.mime()
                )
            );

            ui.label(
                format!(
                    "Engine: {}",
                    category
                        .default_engine()
                )
            );
        }
    );

    ui.add_space(20.0);

    ui.group(
        |ui| {

            ui.label(
                tr(
                    "argument_presets"
                )
            );

            ui.add_space(5.0);

            egui::ComboBox::from_id_salt(
                "argument_preset"
            )
            .selected_text(
                "Preset"
            )
            .show_ui(
                ui,
                |ui| {

                    for preset in
                        category
                            .argument_presets() {

                        if ui
                            .selectable_label(
                                false,
                                preset
                            )
                            .clicked() {

                            *arguments =
                                preset
                                    .to_string();
                        }
                    }
                }
            );

            ui.add_space(15.0);

            ui.label(
                tr(
                    "arguments"
                )
            );

            ui.text_edit_multiline(
                arguments
            );
        }
    );
}
