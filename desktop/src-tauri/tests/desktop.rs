//! The desktop around the window: what a notification may say, and the autostart entry. The tray
//! and the system notification service need a session; they are tried in the end-to-end tests.

use rfe_desktop_lib::desktop::{
    autostart_entry, autostart_is_on, clean_text, set_autostart_in, KINDS,
};
use std::path::Path;
use tempfile::TempDir;

#[test]
fn notification_text_has_no_control_or_direction_characters_and_is_cut_short() {
    assert_eq!(
        clean_text("  Transfer\u{0}\u{7} done\n", 80),
        "Transfer done"
    );
    assert_eq!(clean_text("a\u{202e}b\u{200b}c", 80), "abc");
    let long = "x".repeat(300);
    let cut = clean_text(&long, 240);
    assert_eq!(cut.chars().count(), 240);
    assert!(cut.ends_with('…'));
    // Cut on a character boundary, never in the middle of one.
    let wide = "日".repeat(100);
    assert_eq!(clean_text(&wide, 10).chars().count(), 10);
    assert_eq!(clean_text("", 10), "");
}

#[test]
fn only_known_kinds_exist() {
    assert!(KINDS.contains(&"done") && KINDS.contains(&"test"));
    assert!(!KINDS.contains(&"anything"));
}

#[test]
fn the_autostart_entry_starts_this_program_hidden_and_quotes_its_path() {
    let e = autostart_entry(Path::new("/opt/RFE Desktop/rfe-desktop"));
    assert!(e.starts_with("[Desktop Entry]\n"));
    assert!(
        e.contains("Exec=\"/opt/RFE Desktop/rfe-desktop\" --minimized\n"),
        "{e}"
    );
    assert!(e.contains("Type=Application"));
    // A path cannot add a second command or a field code.
    let e = autostart_entry(Path::new("/tmp/a\"b$c`d\\e%f"));
    assert!(
        e.contains(r#"Exec="/tmp/a\\"b\\$c\\`d\\\\e%%f" --minimized"#),
        "{e}"
    );
    assert_eq!(e.matches("Exec=").count(), 1);
    // A newline in a path cannot start another key.
    let e = autostart_entry(Path::new("/tmp/a\nExec=evil"));
    assert_eq!(e.matches("\nExec=").count(), 1, "{e}");
    assert_eq!(e.lines().count(), 7);
}

#[test]
fn autostart_turns_on_and_off_and_off_twice_is_fine() {
    let config = TempDir::new().unwrap();
    let exe = Path::new("/usr/bin/rfe-desktop");
    assert!(!autostart_is_on(config.path()));
    set_autostart_in(config.path(), exe, true).unwrap();
    assert!(autostart_is_on(config.path()));
    let file = config.path().join("autostart/rfe-desktop.desktop");
    assert!(std::fs::read_to_string(file)
        .unwrap()
        .contains("/usr/bin/rfe-desktop"));
    set_autostart_in(config.path(), exe, false).unwrap();
    assert!(!autostart_is_on(config.path()));
    set_autostart_in(config.path(), exe, false).unwrap();
}

#[test]
fn autostart_refuses_a_program_it_cannot_name_in_full() {
    let config = TempDir::new().unwrap();
    let e = set_autostart_in(config.path(), Path::new("rfe-desktop"), true).unwrap_err();
    assert!(e.contains("cannot find where"), "{e}");
    assert!(!autostart_is_on(config.path()));
}
