import 'package:permission_handler/permission_handler.dart';

Future<bool> requestPermissions() async {
  Map<Permission, PermissionStatus> statuses = await [
    Permission.location,
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();

  return statuses.values.every((status) => status.isGranted);
}
