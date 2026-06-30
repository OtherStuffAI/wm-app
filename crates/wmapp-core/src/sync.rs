#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LocalItemState {
    OnlineOnly,
    Hydrating,
    Cached,
    Pinned,
    Dirty,
    Conflicted,
    Deleted,
}

#[derive(Debug, Default)]
pub struct SyncEngine;

impl SyncEngine {
    pub fn new() -> Self {
        Self
    }
}
