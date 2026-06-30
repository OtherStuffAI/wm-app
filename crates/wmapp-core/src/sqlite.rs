use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct SqliteIndexConfig {
    pub path: PathBuf,
}

#[derive(Debug, Clone)]
pub struct SqliteIndex {
    config: SqliteIndexConfig,
}

impl SqliteIndex {
    pub fn new(config: SqliteIndexConfig) -> Self {
        Self { config }
    }

    pub fn path(&self) -> &PathBuf {
        &self.config.path
    }
}
