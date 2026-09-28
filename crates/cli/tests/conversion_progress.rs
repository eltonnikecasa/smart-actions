use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

fn executable(path: &Path, contents: &str) {
    fs::write(path, contents).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn conversion_process_reports_progress_and_preserves_errors_and_arguments() {
    let root = std::env::temp_dir().join(format!("smart-actions-progress-{}", std::process::id()));
    fs::create_dir_all(root.join("config/smart-actions")).unwrap();
    fs::create_dir_all(root.join("presets")).unwrap();
    fs::write(root.join("input"), "fixture").unwrap();
    fs::write(
        root.join("config/smart-actions/config.yaml"),
        format!(
            "locale: en\npresets_dir: {}\ndefault_output_dir: {}\n",
            root.join("presets").display(),
            root.display()
        ),
    )
    .unwrap();
    executable(
        &root.join("ffprobe"),
        "#!/bin/sh\nprintf '%s\\n' \"$DURATION\"\n",
    );
    executable(
        &root.join("ffmpeg"),
        r#"#!/bin/sh
printf '%s\n' "$@" > "$FIXTURE/args"
printf 'out_time_us=2500000\nprogress=continue\nout_time_us=10000000\nprogress=end\n'
printf 'original converter diagnostic\n' >&2
exit "$CONVERTER_EXIT"
"#,
    );
    for (group, duration, status, expected) in [
        ("video", "10", "0", true),
        ("video", "N/A", "0", false),
        ("image", "10", "0", false),
        ("video", "10", "7", true),
    ] {
        fs::write(root.join("presets/test.yaml"), format!(
            "id: test\nenabled: true\nmin_files: 1\nmax_files: 1\nengine: ffmpeg\nmenu:\n  group: {group}\n  priority: 1\nmime: [video/*]\noutput:\n  extension: mp4\n  suffix: converted\n  preserve_extension: false\ncommand:\n  args: [-c:v, libx264, -crf, '23']\n"
        )).unwrap();
        let result = Command::new(env!("CARGO_BIN_EXE_cli"))
            .args(["invoke", "test"])
            .arg(root.join("input"))
            .env("XDG_CONFIG_HOME", root.join("config"))
            .env("PATH", &root)
            .env("FIXTURE", &root)
            .env("SMART_ACTIONS_PROGRESS", "1")
            .env("DURATION", duration)
            .env("CONVERTER_EXIT", status)
            .output()
            .unwrap();
        let stdout = String::from_utf8(result.stdout).unwrap();
        let stderr = String::from_utf8(result.stderr).unwrap();
        assert_eq!(result.status.success(), status == "0", "{stderr}");
        assert_eq!(
            stdout.contains("SMART_ACTIONS_PROGRESS=25"),
            expected,
            "{stdout}"
        );
        assert!(!stdout.contains("SMART_ACTIONS_PROGRESS=100"));
        assert!(stderr.contains("original converter diagnostic"));
        let args = fs::read_to_string(root.join("args")).unwrap();
        let expected = format!(
            "-i\n{}\n-c:v\nlibx264\n-crf\n23\n{}\n-progress\npipe:1\n-nostats\n",
            root.join("input").display(),
            root.join("input_converted.mp4").display()
        );
        assert_eq!(args, expected, "encoding arguments must remain unchanged");
    }
    fs::remove_dir_all(root).unwrap();
}
