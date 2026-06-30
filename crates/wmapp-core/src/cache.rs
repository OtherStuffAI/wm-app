use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct ObjectCacheConfig {
    pub root: PathBuf,
}

#[derive(Debug, Clone)]
pub struct ObjectCache {
    config: ObjectCacheConfig,
}

impl ObjectCache {
    pub fn new(config: ObjectCacheConfig) -> Self {
        Self { config }
    }

    pub fn root(&self) -> &PathBuf {
        &self.config.root
    }
}
