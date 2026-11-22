import 'package:flutter/foundation.dart';

import '../../core/auth/saved_credentials.dart';
import '../../core/settings/app_settings.dart';
import 'campus_network_controller.dart';

Future<void> connectCampusNetworkAtStartup({
  required String? sessionAccount,
  required Future<SavedCredentials?> Function() readCredentials,
  AppSettingsStore settingsStore = const AppSettingsStore(),
  Future<void> Function(AppSettings, String, SavedCredentials?) connect =
      _connect,
}) async {
  var account = sessionAccount?.trim();
  SavedCredentials? saved;
  if (account == null || account.isEmpty) {
    saved = await readCredentials();
    account = saved?.username.trim().split('@').first;
  }
  if (account == null || account.isEmpty) return;
  final settings = await settingsStore.readForAccount(account);
  if (!settings.autoStart || !settings.campusAutoConnect) return;
  saved ??= await readCredentials();
  await connect(settings, account, saved);
}

Future<void> _connect(
  AppSettings initial,
  String account,
  SavedCredentials? saved,
) async {
  final settings = AppSettingsController(initial: initial);
  final controller = CampusNetworkController.forPlatform(
    settings: settings,
    readCredentials: () async => saved,
    account: account,
    platform: TargetPlatform.windows,
  );
  try {
    await controller.connectFlow(settings.campusWifiSsid);
  } finally {
    controller.dispose();
    settings.dispose();
  }
}
