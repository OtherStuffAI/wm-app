class AppConfig {
  const AppConfig({
    required this.towerUrl,
    required this.workspaceId,
    required this.channelId,
    required this.deviceSecret,
  });

  factory AppConfig.defaults() {
    return const AppConfig(
      towerUrl: 'http://127.0.0.1:3100',
      workspaceId: '',
      channelId: '',
      deviceSecret: '',
    );
  }

  final String towerUrl;
  final String workspaceId;
  final String channelId;
  final String deviceSecret;

  bool get hasTower => towerUrl.trim().isNotEmpty;
  bool get hasWorkspace => workspaceId.trim().isNotEmpty;
  bool get hasChannel => channelId.trim().isNotEmpty;
  bool get hasDeviceSecret => deviceSecret.trim().isNotEmpty;

  bool get canSync => hasTower && hasWorkspace && hasChannel && hasDeviceSecret;

  AppConfig copyWith({
    String? towerUrl,
    String? workspaceId,
    String? channelId,
    String? deviceSecret,
  }) {
    return AppConfig(
      towerUrl: towerUrl ?? this.towerUrl,
      workspaceId: workspaceId ?? this.workspaceId,
      channelId: channelId ?? this.channelId,
      deviceSecret: deviceSecret ?? this.deviceSecret,
    );
  }
}
