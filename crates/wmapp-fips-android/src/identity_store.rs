use fips::{Identity, encode_nsec};
use std::fs::{self, OpenOptions};
use std::io::{ErrorKind, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;
use zeroize::{Zeroize, Zeroizing};

use crate::NativeError;

pub(crate) fn load_or_create(path: &Path) -> Result<Identity, NativeError> {
    if path.exists() {
        return load(path);
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    let identity = Identity::generate();
    let mut encoded = Zeroizing::new(encode_nsec(&identity.keypair().secret_key()));
    match OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
    {
        Ok(mut file) => {
            file.write_all(encoded.as_bytes())?;
            file.write_all(b"\n")?;
            file.sync_all()?;
            drop(file);
            fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
            encoded.zeroize();
            Ok(identity)
        }
        Err(error) if error.kind() == ErrorKind::AlreadyExists => load(path),
        Err(error) => Err(error.into()),
    }
}

fn load(path: &Path) -> Result<Identity, NativeError> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.file_type().is_file() || metadata.file_type().is_symlink() {
        return Err(NativeError::Identity(
            "identity path is not a regular file".into(),
        ));
    }
    let mut secret = Zeroizing::new(fs::read_to_string(path)?);
    let identity = Identity::from_secret_str(secret.trim())
        .map_err(|_| NativeError::Identity("stored identity is invalid".into()))?;
    secret.zeroize();
    Ok(identity)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_is_persistent_private_and_error_safe() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("fips.machine.key");
        let first = load_or_create(&path).unwrap();
        let second = load_or_create(&path).unwrap();
        assert_eq!(first.npub(), second.npub());
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(!format!("{:?}", first).contains("nsec1"));
    }
}
