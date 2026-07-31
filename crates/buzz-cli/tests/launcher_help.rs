#[cfg(unix)]
mod unix {
    use std::os::unix::process::CommandExt;
    use std::process::Command;

    fn help(launcher: &str) -> String {
        let output = Command::new(env!("CARGO_BIN_EXE_buzz"))
            .arg0(launcher)
            .arg("--help")
            .output()
            .expect("run bundled CLI");
        assert!(output.status.success(), "{launcher} --help must succeed");
        String::from_utf8(output.stdout).expect("help is UTF-8")
    }

    #[test]
    fn canonical_and_legacy_launchers_emit_identical_zion_help() {
        let canonical = help("zion");
        let legacy = help("buzz");
        assert_eq!(canonical, legacy);
        assert!(canonical.contains("Zion CLI"));
        assert!(
            !canonical.to_ascii_lowercase().contains("buzz"),
            "newly emitted help must be Zion-only:\n{canonical}"
        );
    }
}
