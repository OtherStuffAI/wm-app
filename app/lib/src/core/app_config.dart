class AppConfig {
  const AppConfig({
    required this.towerUrl,
    required this.appNpub,
    required this.flightDeckUrl,
    required this.workspaceId,
    required this.workspaceServiceNpub,
    required this.channelId,
    required this.deviceSecret,
    required this.registrationSecret,
    required this.deviceNpub,
    required this.devicePublicKeyHex,
    required this.trustedOrigins,
    required this.rememberNip98Approvals,
  });

  factory AppConfig.defaults() {
    return const AppConfig(
      towerUrl: 'http://127.0.0.1:3100',
      appNpub:
          'npub1hd37reqgfcnz3pvzj4grknd2nkzc94p9ercmunrxx22razr2rfxsw6dns5',
      flightDeckUrl: 'https://near-tea-crab.rick.runwingman.com',
      workspaceId: '2e5caefd-dd65-45d2-b747-ee874e8e5fc9',
      workspaceServiceNpub:
          'npub1995l838tl29llpxwvpdv6hc66cttrt6hrr8xyeq7kmdqevkeyk0qwvfxlc',
      channelId: 'd8d00881-ac84-41eb-ab0d-2c2afb77ddf3',
      deviceSecret: '',
      registrationSecret: '',
      deviceNpub: '',
      devicePublicKeyHex: '',
      trustedOrigins: [
        'http://127.0.0.1:3100',
        'http://127.0.0.1:8093',
        'https://kind-net-duck.rick.runwingman.com',
        'https://near-tea-crab.rick.runwingman.com',
        'https://rick.runwingman.com',
      ],
      rememberNip98Approvals: true,
    );
  }

  final String towerUrl;
  final String appNpub;
  final String flightDeckUrl;
  final String workspaceId;
  final String workspaceServiceNpub;
  final String channelId;
  final String deviceSecret;
  final String registrationSecret;
  final String deviceNpub;
  final String devicePublicKeyHex;
  final List<String> trustedOrigins;
  final bool rememberNip98Approvals;

  bool get hasTower => towerUrl.trim().isNotEmpty;
  bool get hasAppNpub => appNpub.trim().isNotEmpty;
  bool get hasWorkspace => workspaceId.trim().isNotEmpty;
  bool get hasWorkspaceService => workspaceServiceNpub.trim().isNotEmpty;
  bool get hasChannel => channelId.trim().isNotEmpty;
  bool get hasDeviceSecret => deviceSecret.trim().isNotEmpty;
  bool get hasDeviceNpub => deviceNpub.trim().isNotEmpty;
  bool get hasDevicePublicKeyHex => devicePublicKeyHex.trim().isNotEmpty;

  bool get canSync =>
      hasTower && hasAppNpub && hasWorkspace && hasChannel && hasDeviceSecret;
  bool get canRegisterDevice =>
      hasTower && hasWorkspaceService && hasDeviceNpub;

  AppConfig copyWith({
    String? towerUrl,
    String? appNpub,
    String? flightDeckUrl,
    String? workspaceId,
    String? workspaceServiceNpub,
    String? channelId,
    String? deviceSecret,
    String? registrationSecret,
    String? deviceNpub,
    String? devicePublicKeyHex,
    List<String>? trustedOrigins,
    bool? rememberNip98Approvals,
  }) {
    return AppConfig(
      towerUrl: towerUrl ?? this.towerUrl,
      appNpub: appNpub ?? this.appNpub,
      flightDeckUrl: flightDeckUrl ?? this.flightDeckUrl,
      workspaceId: workspaceId ?? this.workspaceId,
      workspaceServiceNpub: workspaceServiceNpub ?? this.workspaceServiceNpub,
      channelId: channelId ?? this.channelId,
      deviceSecret: deviceSecret ?? this.deviceSecret,
      registrationSecret: registrationSecret ?? this.registrationSecret,
      deviceNpub: deviceNpub ?? this.deviceNpub,
      devicePublicKeyHex: devicePublicKeyHex ?? this.devicePublicKeyHex,
      trustedOrigins: trustedOrigins ?? this.trustedOrigins,
      rememberNip98Approvals:
          rememberNip98Approvals ?? this.rememberNip98Approvals,
    );
  }

  List<String> effectiveTrustedOrigins() {
    final origins = <String>{
      for (final origin in trustedOrigins) origin.trim(),
      _originOf(towerUrl),
      _originOf(flightDeckUrl),
    }..remove('');
    return origins.toList(growable: false);
  }

  static String _originOf(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    if (uri.hasPort) return '${uri.scheme}://${uri.host}:${uri.port}';
    return '${uri.scheme}://${uri.host}';
  }
}
