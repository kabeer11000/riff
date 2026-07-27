import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() async {
  if (kIsWeb) {
    // Our own track menu handles right-click; the browser's menu would
    // otherwise open on top of it.
    WidgetsFlutterBinding.ensureInitialized();
    await BrowserContextMenu.disableContextMenu();
  }
  runApp(const ProviderScope(child: RiffApp()));
}
