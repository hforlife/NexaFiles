import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppTab { files, library, recents, tools }

/// Selected bottom-navigation tab. Screens switch tabs through this provider
/// instead of pushing a new shell route.
final currentTabProvider = StateProvider<AppTab>((_) => AppTab.files);
