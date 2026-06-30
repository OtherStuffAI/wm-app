use thiserror::Error;

#[derive(Debug, Error)]
pub enum TowerClientError {
    #[error("Tower route is not supported by the current contract: {0}")]
    UnsupportedByTowerContract(&'static str),
}

pub trait TowerDriveClient {
    fn list_workspaces(&self) -> Result<(), TowerClientError>;
    fn list_scopes(&self, workspace_id: &str) -> Result<(), TowerClientError>;
    fn list_channels(&self, workspace_id: &str, scope_id: &str) -> Result<(), TowerClientError>;
    fn list_children(&self, workspace_id: &str, channel_id: &str) -> Result<(), TowerClientError>;
    fn get_file(&self, workspace_id: &str, file_id: &str) -> Result<(), TowerClientError>;
    fn get_file_content(&self, workspace_id: &str, file_id: &str) -> Result<(), TowerClientError>;
    fn poll_events(&self, workspace_id: &str, cursor: Option<&str>)
        -> Result<(), TowerClientError>;

    fn replace_file_content(&self) -> Result<(), TowerClientError> {
        Err(TowerClientError::UnsupportedByTowerContract(
            "file content replacement requires WMAPP TOWER-GAP-03",
        ))
    }

    fn delete_file(&self) -> Result<(), TowerClientError> {
        Err(TowerClientError::UnsupportedByTowerContract(
            "file tombstones require WMAPP TOWER-GAP-04",
        ))
    }
}
