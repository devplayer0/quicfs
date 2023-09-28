use std::error::Error;
use std::path::PathBuf;

use clap::{Parser, ValueHint};
use signal_hook::consts::{SIGINT, SIGTERM};
use signal_hook::iterator::Signals;

mod fs;

/// quicfs client
#[derive(Debug, Parser)]
#[command(author, version)]
struct Args {
    #[arg(value_hint = ValueHint::DirPath)]
    pub mountpoint: PathBuf,
}

fn main() -> Result<(), Box<dyn Error>> {
    let args = Args::parse();

    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));

    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    let fs_session = fuser::spawn_mount2(fs::QuicFS::new(), &args.mountpoint, &[])?;

    for _ in Signals::new(&[SIGINT, SIGTERM])?.forever() {
        fs_session.join();
        break;
    }

    Ok(())
}
