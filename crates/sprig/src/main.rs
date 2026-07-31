fn main() {
    if let Err(e) = dispatch() {
        eprintln!("{e}");
        std::process::exit(1);
    }
}

fn dispatch() -> Result<(), String> {
    let argv0 = std::env::args().next().unwrap_or_default();
    let cmd = std::path::Path::new(&argv0)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    match cmd.as_str() {
        "zion-acp" | "buzz-acp" => buzz_acp::run().map_err(|e| e.to_string()),
        "zion-agent" | "buzz-agent" => buzz_agent::run().map_err(|e| e.to_string()),
        "sprig" => match std::env::args().nth(1).as_deref() {
            Some("-V") | Some("--version") => {
                println!("sprig {}", env!("CARGO_PKG_VERSION"));
                Ok(())
            }
            Some("-h") | Some("--help") | None => {
                print_usage();
                if std::env::args().len() <= 1 {
                    Err("error: invoke Sprig via a personality symlink".into())
                } else {
                    Ok(())
                }
            }
            Some(other) => {
                print_usage();
                Err(format!(
                    "error: unknown Sprig option or personality: {other}"
                ))
            }
        },
        // Zion Dev MCP also handles its own multicall names: rg, tree,
        // zion, legacy aliases, git-credential-nostr, and git-sign-nostr.
        _ => buzz_dev_mcp::run().map_err(|e| e.to_string()),
    }
}

fn print_usage() {
    println!(
        "Sprig — all-in-one Zion ACP harness, agent, and developer MCP\n\n\
Sprig is a multicall binary. Invoke it through one of the personality names:\n\n\
  zion-acp       ACP harness\n  zion-agent     ACP-compliant agent\n  zion-dev-mcp   Developer MCP server\n\n\
Developer MCP helper names are also supported: rg, tree, zion, git-credential-nostr, git-sign-nostr.\n\n\
Installers can create links with:\n  ln -s sprig zion-acp\n  ln -s sprig zion-agent\n  ln -s sprig zion-dev-mcp"
    );
}
