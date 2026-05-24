mod models {

    pub mod category;
}

mod screens {

    pub mod list;

    pub mod editor;
}

mod services {

    pub mod preset_save;
}

use eframe::egui;

use smart_actions_core::config::load_config;

use smart_actions_core::i18n::{
    load_language,
    Language,
};

use smart_actions_core::preset::Preset;

use smart_actions_core::presets::load_all_presets;

use models::category::FileCategory;

use screens::list::show_list_screen;

use screens::editor::show_editor_screen;

use services::preset_save::{
    save_preset,
    delete_preset,
};

fn main() -> eframe::Result<()> {

    let options =
        eframe::NativeOptions {

            viewport:
                egui::ViewportBuilder::default()
                    .with_inner_size(
                        [760.0, 820.0]
                    ),

            ..Default::default()
        };

    eframe::run_native(
        "Smart Actions",
        options,
        Box::new(|_cc| {

            Ok(
                Box::new(
                    ManagerApp::new()
                )
            )
        }),
    )
}

enum Screen {

    List,

    Editor,
}

struct ManagerApp {

    presets: Vec<Preset>,

    language: Language,

    selected: Option<usize>,

    screen: Screen,

    category: FileCategory,

    output_format: String,

    display_name: String,

    enabled: bool,

    multi_file: bool,

    arguments: String,
}

impl ManagerApp {

    fn tr(
        language: &Language,
        key: &str,
    ) -> String {

        language
            .ui
            .get(key)
            .cloned()
            .unwrap_or(
                key.to_string()
            )
    }

    fn reload_presets(
        &mut self
    ) {

        let config =
            load_config()
                .expect(
                    "Failed to reload config"
                );

        self.presets =
            load_all_presets(
                &config.presets_dir
            );
    }

    fn new() -> Self {

        let config =
            load_config()
                .expect(
                    "Failed to load config"
                );

        let presets =
            load_all_presets(
                &config.presets_dir
            );

        let language =
            load_language(
                &config.locale
            )
            .expect(
                "Failed to load language"
            );

        Self {

            presets,

            language,

            selected: None,

            screen: Screen::List,

            category:
                FileCategory::Video,

            output_format:
                String::from("mp4"),

            display_name:
                String::new(),

            enabled: true,

            multi_file: false,

            arguments:
                String::from(
                    "-crf 23"
                ),
        }
    }
}

impl eframe::App for ManagerApp {

    fn update(

        &mut self,

        ctx: &egui::Context,

        _frame: &mut eframe::Frame,
    ) {

        egui::CentralPanel::default()
            .show(
                ctx,
                |ui| {

                match self.screen {

                    Screen::List => {

                        show_list_screen(

                            ui,

                            &self.presets,

                            &self.language,

                            &mut self.selected,
                        );

                        ui.add_space(20.0);

                        ui.separator();

                        ui.add_space(10.0);

                        ui.horizontal_centered(
                            |ui| {

                                if ui
                                    .button(
                                        Self::tr(
                                            &self.language,
                                            "new"
                                        )
                                    )
                                    .clicked() {

                                    self.display_name =
                                        String::new();

                                    self.arguments =
                                        String::from(
                                            "-crf 23"
                                        );

                                    self.screen =
                                        Screen::Editor;
                                }

                                if self.selected
                                    .is_some() {

                                    if ui
                                        .button(
                                            Self::tr(
                                                &self.language,
                                                "edit"
                                            )
                                        )
                                        .clicked() {

                                        self.screen =
                                            Screen::Editor;
                                    }

                                    if ui
                                        .button(
                                            Self::tr(
                                                &self.language,
                                                "delete"
                                            )
                                        )
                                        .clicked() {

                                        if let Some(
                                            index
                                        ) = self.selected {

                                            let preset =
                                                &self.presets[index];

                                            delete_preset(
                                                &preset.id
                                            );

                                            self.reload_presets();

                                            self.selected =
                                                None;
                                        }
                                    }
                                }
                            }
                        );
                    }

                    Screen::Editor => {

                        let language =
                            self.language.clone();

                        show_editor_screen(

                            ui,

                            &|k| {

                                Self::tr(
                                    &language,
                                    k
                                )
                            },

                            &mut self.category,

                            &mut self.output_format,

                            &mut self.display_name,

                            &mut self.enabled,

                            &mut self.multi_file,

                            &mut self.arguments,
                        );

                        ui.add_space(30.0);

                        ui.separator();

                        ui.add_space(10.0);

                        ui.horizontal_centered(
                            |ui| {

                                if ui
                                    .button(
                                        Self::tr(
                                            &self.language,
                                            "cancel"
                                        )
                                    )
                                    .clicked() {

                                    self.screen =
                                        Screen::List;
                                }

                                if ui
                                    .button(
                                        Self::tr(
                                            &self.language,
                                            "save"
                                        )
                                    )
                                    .clicked() {

                                    save_preset(

                                        &self.display_name,

                                        self.enabled,

                                        self.multi_file,

                                        &self.category,

                                        &self.arguments,

                                        &self.output_format,
                                    );

                                    self.reload_presets();

                                    self.screen =
                                        Screen::List;
                                }
                            }
                        );
                    }
                }
            });
    }
}
