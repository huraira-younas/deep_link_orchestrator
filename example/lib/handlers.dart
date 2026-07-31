import 'package:deep_link_orchestrator/deep_link_orchestrator.dart';
import 'package:flutter/widgets.dart';

import 'intents.dart';

class ProfileHandler extends TypedDeepLinkHandler<ProfileIntent> {
  ProfileHandler(this.onNavigate);

  final void Function(String userId) onNavigate;

  @override
  Future<void> onHandle(ProfileIntent intent, DeepLinkHandlerContext _) async {
    debugPrint('[ProfileHandler] Navigating to user: ${intent.userId}');
    onNavigate(intent.userId);
  }
}

class InviteHandler extends TypedDeepLinkHandler<InviteIntent> {
  InviteHandler(this.onInvite);

  final void Function(String code) onInvite;

  /// Deferred through the pending store until the user signs in.
  @override
  bool get requiresAuthentication => true;

  @override
  Future<void> onHandle(InviteIntent intent, DeepLinkHandlerContext _) async {
    debugPrint('[InviteHandler] Accepting invite: ${intent.inviteCode}');
    onInvite(intent.inviteCode);
  }
}

class SettingsHandler extends TypedDeepLinkHandler<SettingsIntent> {
  SettingsHandler(this.onNavigate);

  final void Function(String? section) onNavigate;

  @override
  Future<void> onHandle(SettingsIntent intent, DeepLinkHandlerContext _) async {
    debugPrint('[SettingsHandler] Opening: ${intent.section ?? "root"}');
    onNavigate(intent.section);
  }
}
