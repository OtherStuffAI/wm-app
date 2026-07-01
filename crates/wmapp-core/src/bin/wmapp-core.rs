use clap::{Parser, Subcommand};
use serde::Serialize;
use wmapp_core::{
    DeviceKey, DriveItemType, DriveTreeOptions, Nip98Request, Nip98Signer, TowerClient,
    TowerClientConfig,
};

#[derive(Parser)]
#[command(name = "wmapp-core")]
#[command(about = "Wingman App native core development CLI")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Print native core status, optionally including live Tower read status.
    Status(StatusArgs),
    /// List visible Drive file/folder items from Tower.
    ListFiles(ListFilesArgs),
    /// Generate or inspect development device keys.
    Device {
        #[command(subcommand)]
        command: DeviceCommand,
    },
    /// Sign a NIP-98 HTTP authorization event.
    SignNip98 {
        #[arg(long)]
        secret: String,
        #[arg(long)]
        method: String,
        #[arg(long)]
        url: String,
        #[arg(long)]
        body: Option<String>,
    },
}

#[derive(Parser, Debug, Clone, Default)]
struct TowerReadArgs {
    /// Tower base URL. Falls back to TOWER_URL or FLIGHTDECK_TOWER_URL.
    #[arg(long)]
    tower_url: Option<String>,
    /// Flight Deck PG app npub. Falls back to FLIGHTDECK_APP_NPUB.
    #[arg(long)]
    app_npub: Option<String>,
    /// Hex or nsec key used for NIP-98 signing. Falls back to WINGMAN_NSEC, WINGMAN_PRIV, or AGENT_NSEC.
    #[arg(long)]
    secret: Option<String>,
}

#[derive(Parser, Debug, Clone, Default)]
struct StatusArgs {
    #[command(flatten)]
    tower: TowerReadArgs,
    /// Optional workspace id for descriptor/me checks.
    #[arg(long)]
    workspace_id: Option<String>,
}

#[derive(Parser, Debug, Clone)]
struct ListFilesArgs {
    #[command(flatten)]
    tower: TowerReadArgs,
    /// Workspace id to list.
    #[arg(long)]
    workspace_id: String,
    /// Optional scope filter.
    #[arg(long)]
    scope_id: Option<String>,
    /// Optional channel filter.
    #[arg(long)]
    channel_id: Option<String>,
    /// Optional parent folder filter.
    #[arg(long)]
    parent_folder_id: Option<String>,
    /// Optional Drive tree cursor.
    #[arg(long)]
    cursor: Option<String>,
    /// Page size.
    #[arg(long, default_value_t = 100)]
    limit: u16,
}

#[derive(Subcommand)]
enum DeviceCommand {
    /// Generate a new local development device key.
    Generate {
        /// Include the nsec in output. Use only for development.
        #[arg(long)]
        show_secret: bool,
    },
    /// Import a hex or nsec key and print its public identity.
    Import {
        #[arg(long)]
        secret: String,
    },
}

#[derive(Serialize)]
struct DeviceOutput {
    npub: String,
    public_key_hex: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    nsec: Option<String>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();
    match cli.command {
        Command::Status(args) => print_status(args)?,
        Command::ListFiles(args) => list_files(args)?,
        Command::Device { command } => match command {
            DeviceCommand::Generate { show_secret } => {
                let key = DeviceKey::generate();
                print_device(&key, show_secret)?;
            }
            DeviceCommand::Import { secret } => {
                let key = DeviceKey::import(&secret)?;
                print_device(&key, false)?;
            }
        },
        Command::SignNip98 {
            secret,
            method,
            url,
            body,
        } => {
            let key = DeviceKey::import(&secret)?;
            let mut request = Nip98Request::new(method, url)?;
            if let Some(body) = body {
                request = request.with_body(body.into_bytes());
            }
            let event = Nip98Signer::new(key).sign(request)?;
            print_json(&serde_json::json!({
                "authorization": event.authorization_header()?,
                "event": event
            }))?;
        }
    }
    Ok(())
}

fn print_status(args: StatusArgs) -> Result<(), Box<dyn std::error::Error>> {
    match tower_client_from_args(&args.tower, false)? {
        Some(client) => {
            let service = client.service()?;
            let workspaces = client.list_workspaces()?;
            let mut workspace = None;
            let mut me = None;
            if let Some(workspace_id) = args.workspace_id.as_deref() {
                workspace = Some(client.workspace_descriptor(workspace_id)?);
                me = Some(client.workspace_me(workspace_id)?);
            }
            print_json(&serde_json::json!({
                "ok": true,
                "crate": "wmapp-core",
                "phase": "native-core-spike",
                "tower": {
                    "url": client.config().tower_url.as_str(),
                    "app_npub": client.config().app_npub,
                    "signer_public_key_hex": client.signer_public_key_hex(),
                    "service": service.service,
                    "capabilities": service.capabilities,
                    "workspace_count": workspaces.workspaces.len(),
                    "workspaces": workspaces.workspaces,
                    "workspace": workspace,
                    "me": me
                }
            }))?;
        }
        None => {
            print_json(&serde_json::json!({
                "ok": true,
                "crate": "wmapp-core",
                "phase": "native-core-spike",
                "tower": {
                    "configured": false,
                    "missing": ["tower_url", "app_npub", "secret"]
                }
            }))?;
        }
    }
    Ok(())
}

fn list_files(args: ListFilesArgs) -> Result<(), Box<dyn std::error::Error>> {
    let client = tower_client_from_args(&args.tower, true)?
        .ok_or("Tower config is required for list-files")?;
    let tree = client.drive_tree(
        &args.workspace_id,
        DriveTreeOptions {
            scope_id: args.scope_id.as_deref(),
            channel_id: args.channel_id.as_deref(),
            parent_folder_id: args.parent_folder_id.as_deref(),
            cursor: args.cursor.as_deref(),
            limit: Some(args.limit),
        },
    )?;
    let file_count = tree
        .items
        .iter()
        .filter(|item| item.item_type == DriveItemType::File)
        .count();
    let folder_count = tree
        .items
        .iter()
        .filter(|item| item.item_type == DriveItemType::Folder)
        .count();
    print_json(&serde_json::json!({
        "ok": true,
        "workspace_id": args.workspace_id,
        "scope_id": args.scope_id,
        "channel_id": args.channel_id,
        "parent_folder_id": args.parent_folder_id,
        "file_count": file_count,
        "folder_count": folder_count,
        "items": tree.items,
        "next_cursor": tree.next_cursor
    }))?;
    Ok(())
}

fn print_device(key: &DeviceKey, show_secret: bool) -> Result<(), Box<dyn std::error::Error>> {
    print_json(&DeviceOutput {
        npub: key.npub()?,
        public_key_hex: key.public_key_hex(),
        nsec: if show_secret { Some(key.nsec()?) } else { None },
    })
}

fn print_json<T: Serialize>(value: &T) -> Result<(), Box<dyn std::error::Error>> {
    println!("{}", serde_json::to_string_pretty(value)?);
    Ok(())
}

fn tower_client_from_args(
    args: &TowerReadArgs,
    required: bool,
) -> Result<Option<TowerClient>, Box<dyn std::error::Error>> {
    let tower_url = args
        .tower_url
        .clone()
        .or_else(|| std::env::var("TOWER_URL").ok())
        .or_else(|| std::env::var("FLIGHTDECK_TOWER_URL").ok());
    let app_npub = args
        .app_npub
        .clone()
        .or_else(|| std::env::var("FLIGHTDECK_APP_NPUB").ok());
    let secret = args
        .secret
        .clone()
        .or_else(|| std::env::var("WINGMAN_NSEC").ok())
        .or_else(|| std::env::var("WINGMAN_PRIV").ok())
        .or_else(|| std::env::var("AGENT_NSEC").ok());

    if tower_url.is_none() && app_npub.is_none() && !required {
        return Ok(None);
    }

    let tower_url = tower_url.ok_or("missing Tower URL; pass --tower-url or set TOWER_URL")?;
    let app_npub =
        app_npub.ok_or("missing app npub; pass --app-npub or set FLIGHTDECK_APP_NPUB")?;
    let secret = secret.ok_or("missing signing key; pass --secret or set WINGMAN_NSEC")?;
    let key = DeviceKey::import(&secret)?;
    let config = TowerClientConfig::new(tower_url, app_npub)?;
    Ok(Some(TowerClient::new(config, key)))
}
