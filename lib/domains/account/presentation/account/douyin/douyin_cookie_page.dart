import 'package:pure_live/core/index.dart';
import 'package:pure_live/domains/account/presentation/account/account_cookie_editor.dart';
import 'package:pure_live/domains/account/presentation/account/douyin/douyin_cookie_controller.dart';
import 'package:pure_live/domains/account/presentation/account/web_cookie_capture.dart';

class DouyinCookiePage extends GetView<DouyinCookieController> {
  const DouyinCookiePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AccountCookieEditorPage(
      controller: controller.cookieController,
      hintText: i18n('douyin_cookie_hint'),
      tipText: i18n('douyin_cookie_tip'),
      onSave: controller.setCookie,
      // Douyin is the one platform whose web session is worth capturing: the
      // viewer signs in on douyin.com inside the app and the cookie is filled
      // and saved automatically instead of being copied out of a desktop
      // browser by hand.
      extraActions: [
        OutlinedButton.icon(
          key: const ValueKey('douyin-cookie-auto-capture'),
          onPressed: _autoCapture,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.language_rounded, size: 18),
          label: Text(
            i18n('cookie_auto_capture'),
            style: AppTextStyles.t14.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Future<void> _autoCapture() async {
    final target = kCookieCaptureTargets['douyin'];
    if (target == null) return;
    final cookie = await WebCookieCapturePage.capture(target);
    if (cookie == null || cookie.isEmpty) return;
    controller.setCookie(cookie);
  }
}
