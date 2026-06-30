use clap::{Parser, Subcommand};
use serde::Serialize;
use wmapp_core::{DeviceKey, Nip98Request, Nip98Signer};

#[derive(Parser)]
#[command(name = "wmapp-core")]
#[command(about = "Wingman App native core development CLI")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Print native core status.
    Status,
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
        Command::Status => print_json(&serde_json::json!({
            "ok": true,
            "crate": "wmapp-core",
            "phase": "native-core-spike"
        }))?,
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
