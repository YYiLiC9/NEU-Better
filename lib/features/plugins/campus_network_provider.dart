import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/auth/credential_store.dart';
import '../auth/auth_controller.dart';
import 'campus_network_controller.dart';

final campusNetworkControllerProvider =
    ChangeNotifierProvider<CampusNetworkController>((ref) {
      final account = ref.watch(
        authControllerProvider.select(
          (state) =>
              state is AuthAuthenticated ? state.session.studentId : null,
        ),
      );
      return CampusNetworkController.forPlatform(
        readCredentials: ref.watch(credentialStoreProvider).read,
        account: account,
        platform: defaultTargetPlatform,
      );
    });
