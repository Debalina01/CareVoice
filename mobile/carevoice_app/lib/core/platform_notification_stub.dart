/// Stub for non-web platforms
class PlatformWebNotification {
  static Future<bool> requestPermission() async => false;
  static bool get hasPermission => false;
  static void show({
    required String title,
    required String body,
    String? tag,
    Function()? onTaken,
    Function()? onMissed,
  }) {}
}
