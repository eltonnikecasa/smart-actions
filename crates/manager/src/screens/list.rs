use eframe::egui;

use smart_actions_core::preset::Preset;

use smart_actions_core::i18n::Language;

// Main screen intentionally minimal.
//
// Presets are separated between:
// - bundled presets
// - user custom presets
//
// This helps users understand
// what belongs to the system
// and what they created.
pub fn show_list_screen(

    ui: &mut egui::Ui,

    presets: &Vec<Preset>,

    language: &Language,

    selected: &mut Option<usize>,
) {

    ui.vertical_centered(
        |ui| {

            ui.add_space(10.0);

            ui.heading(
                &language.app_name
            );

            ui.add_space(15.0);
        }
    );

    ui.separator();

    ui.add_space(10.0);

    // Built-in presets section.
    ui.heading(
        "Built-in"
    );

    ui.add_space(10.0);

    for (
        index,
        preset
    ) in presets
        .iter()
        .enumerate()
        .filter(
            |(_, p)| {

            !p.id.starts_with(
                "custom_"
            )
        }) {

        let is_selected =
            *selected
                == Some(index);

        let display_name =
            preset
                .display_name
                .clone()
                .unwrap_or_else(
                    || {

                    language
                        .actions
                        .get(
                            &preset.id
                        )
                        .cloned()
                        .unwrap_or(
                            preset.id
                                .clone()
                        )
                });

        ui.horizontal(
            |ui| {

                let enabled =
                    if preset.enabled {

                    "✓"

                } else {

                    "○"
                };

                ui.label(
                    enabled
                );

                if ui
                    .selectable_label(
                        is_selected,
                        display_name
                    )
                    .clicked() {

                    *selected =
                        Some(index);
                }
            }
        );

        ui.add_space(4.0);
    }

    ui.add_space(20.0);

    ui.separator();

    ui.add_space(10.0);

    // User presets section.
    ui.heading(
        "Custom"
    );

    ui.add_space(10.0);

    for (
        index,
        preset
    ) in presets
        .iter()
        .enumerate()
        .filter(
            |(_, p)| {

            p.id.starts_with(
                "custom_"
            )
        }) {

        let is_selected =
            *selected
                == Some(index);

        let display_name =
            preset
                .display_name
                .clone()
                .unwrap_or_else(
                    || {

                    preset.id
                        .replace(
                            "_",
                            " "
                        )
                });

        ui.horizontal(
            |ui| {

                let enabled =
                    if preset.enabled {

                    "✓"

                } else {

                    "○"
                };

                ui.label(
                    enabled
                );

                if ui
                    .selectable_label(
                        is_selected,
                        display_name
                    )
                    .clicked() {

                    *selected =
                        Some(index);
                }
            }
        );

        ui.add_space(4.0);
    }
}
