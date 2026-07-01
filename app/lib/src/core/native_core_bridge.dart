import 'app_config.dart';

class NativeCoreBridge {
  Future<CoreStatus> status(AppConfig config) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return CoreStatus(
      ok: true,
      towerUrl: config.towerUrl,
      workspaceId: config.workspaceId,
      channelId: config.channelId,
      deviceConfigured: config.hasDeviceSecret,
      message: 'Flutter bridge shape ready. Native core wiring is next.',
    );
  }

  Future<DriveListing> listDrive(AppConfig config) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return DriveListing(
      items: const [
        DriveItem(
          name: 'Wingman App',
          path: '/Wingman Suite/Wingman App',
          kind: DriveItemKind.folder,
          localState: 'online_only',
        ),
        DriveItem(
          name: 'wmapp-cli-test.txt',
          path: '/Wingman Suite/Wingman App/wmapp-cli-test.txt',
          kind: DriveItemKind.file,
          localState: 'online_only',
        ),
      ],
      message: config.canSync
          ? 'Fixture listing. Connect this bridge to wmapp-core list-items.'
          : 'Configure Tower, workspace, and device key before syncing.',
    );
  }
}

class CoreStatus {
  const CoreStatus({
    required this.ok,
    required this.towerUrl,
    required this.workspaceId,
    required this.channelId,
    required this.deviceConfigured,
    required this.message,
  });

  final bool ok;
  final String towerUrl;
  final String workspaceId;
  final String channelId;
  final bool deviceConfigured;
  final String message;
}

class DriveListing {
  const DriveListing({
    required this.items,
    required this.message,
  });

  final List<DriveItem> items;
  final String message;
}

class DriveItem {
  const DriveItem({
    required this.name,
    required this.path,
    required this.kind,
    required this.localState,
  });

  final String name;
  final String path;
  final DriveItemKind kind;
  final String localState;
}

enum DriveItemKind {
  folder,
  file,
}
