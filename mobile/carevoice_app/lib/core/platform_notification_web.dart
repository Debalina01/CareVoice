// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Browser Notification API integration for Flutter Web
class PlatformWebNotification {
  static Future<bool> requestPermission() async {
    if (!html.Notification.supported) return false;
    final permission = await html.Notification.requestPermission();
    return permission == 'granted';
  }

  static bool get hasPermission {
    if (!html.Notification.supported) return false;
    return html.Notification.permission == 'granted';
  }

  static void show({
    required String title,
    required String body,
    String? tag,
    Function()? onTaken,
    Function()? onMissed,
  }) {
    if (!html.Notification.supported) return;

    if (html.Notification.permission == 'granted') {
      final notif = html.Notification(
        title,
        body: body,
        icon: 'favicon.png',
        tag: tag,
      );

      notif.onClick.listen((_) {
        notif.close();
      });
    } else if (html.Notification.permission != 'denied') {
      html.Notification.requestPermission().then((perm) {
        if (perm == 'granted') {
          show(
            title: title,
            body: body,
            tag: tag,
            onTaken: onTaken,
            onMissed: onMissed,
          );
        }
      });
    }
  }
}
