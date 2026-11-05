import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

import 'app_launcher_service.dart';

/// The floating bubble (like a chat head) drawn over other apps while the
/// driver is online and has left the app, so one tap brings them back.
///
/// It needs the "display over other apps" permission, which the ride-offer
/// permission flow already asks for; nothing is requested here, so a driver who
/// has not granted it simply gets no bubble.
class BubbleService {
  BubbleService._();

  static bool _shown = false;
  static bool _askedForPermission = false;

  /// Opens the "display over other apps" settings page once per app run when it
  /// is missing. Without it the bubble can never be drawn, and nothing else says so.
  static Future<void> ensurePermission() async {
    if (_askedForPermission) return;
    try {
      if (await FlutterOverlayWindow.isPermissionGranted()) return;
      _askedForPermission = true;
      await FlutterOverlayWindow.requestPermission();
    } catch (error) {
      developer.log('Overlay permission request failed: $error', name: 'bubble');
    }
  }
  static StreamSubscription<dynamic>? _tapSub;

  /// Listens for taps on the bubble. Safe to call more than once.
  static void init() {
    _tapSub ??= FlutterOverlayWindow.overlayListener.listen((event) {
      if (event == 'open') {
        AppLauncherService.bringToForeground();
        hide();
      }
    });
  }

  /// Shown only for an online driver who has left the app.
  static Future<void> sync({required bool appInBackground, required bool online}) async {
    if (appInBackground && online) {
      await show();
    } else {
      await hide();
    }
  }

  static Future<void> show() async {
    // Claimed before any await: `hidden` and `paused` arrive back to back, and two
    // overlapping starts made the plugin tear the window down as soon as it was up.
    if (_shown) return;
    _shown = true;
    try {
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        developer.log('No overlay permission, bubble not shown', name: 'bubble');
        _shown = false;
        return;
      }
      await FlutterOverlayWindow.showOverlay(
        height: 140,
        width: 140,
        alignment: OverlayAlignment.centerRight,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        overlayTitle: 'KrantiCabs Partner',
        overlayContent: 'You are online. Tap the bubble to open the app.',
      );
    } catch (error) {
      _shown = false;
      developer.log('Could not show the bubble: $error', name: 'bubble');
    }
  }

  static Future<void> hide() async {
    _shown = false;
    try {
      // Not gated on our own flag: the bubble can outlive it (it is a separate
      // service, and a tap on it opens the app from outside), so ask the plugin.
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (error) {
      developer.log('Could not hide the bubble: $error', name: 'bubble');
    }
  }
}

/// What the overlay window draws: the Kranti logo in a gold ring. Runs in its own
/// isolate (see `overlayMain`), so it holds no app state.
class BubbleOverlay extends StatelessWidget {
  const BubbleOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: GestureDetector(
          onTap: () async {
            // The overlay's own engine overwrites the plugin's channel to the app,
            // so shareData never arrives; opening the app's link does the job.
            try {
              // Works without a foreground activity (url_launcher needs one).
              await const AndroidIntent(
                action: 'action_view',
                data: 'kranticabs-partner://open',
                package: 'com.kranticabs.delivery',
                flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
              ).launch();
            } catch (error) {
              debugPrint('[bubble] open failed: $error');
              FlutterOverlayWindow.shareData('open');
            }
          },
          child: Container(
            width: 92,
            height: 92,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: const Color(0xFFF5B400), width: 3),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 3))],
            ),
            child: ClipOval(child: Image.asset('assets/logo.webp', fit: BoxFit.cover)),
          ),
        ),
      ),
    );
  }
}
