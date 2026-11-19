import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class FullscreenHelper {
  static Future<void> apply(Orientation orientation) async {
    if (kIsWeb || !Platform.isIOS) return;
    if (orientation == Orientation.landscape) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: <SystemUiOverlay>[],
      );
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: <SystemUiOverlay>[SystemUiOverlay.top],
      );
    }
  }
}
