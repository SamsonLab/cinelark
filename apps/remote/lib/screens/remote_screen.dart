import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/remote_controller.dart';
import '../models/remote_state.dart';
import '../widgets/directional_pad.dart';
import '../widgets/playback_controls.dart';

class RemoteScreen extends StatelessWidget {
  const RemoteScreen({super.key, required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    final isConnected = controller.isConnected;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(controller.showDevices());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Devices',
            onPressed: () => unawaited(controller.showDevices()),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CineLark Remote'),
              Text(
                controller.pairedMac?.displayName ?? 'Mac',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Colors.white60),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.circle,
                size: 10,
                color: isConnected ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'activate') controller.activateMac();
                if (value == 'forget') controller.forget();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'activate',
                  child: Text('Bring Mac Forward'),
                ),
                PopupMenuItem(value: 'forget', child: Text('Forget This Mac')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            if (!isConnected) const _ReconnectBanner(),
            if (controller.errorCode != null && isConnected)
              _ErrorBanner(
                code: controller.errorCode!,
                onDismiss: controller.dismissError,
              ),
            Expanded(child: _contextualBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _contextualBody(BuildContext context) {
    final playback = controller.playbackSnapshot;
    if (playback?.isActive == true) {
      return PlaybackControls(controller: controller, snapshot: playback!);
    }
    final app = controller.appSnapshot;
    if (app?.phase == 'signedOut') {
      return _LoginRemote(controller: controller);
    }
    if (app == null && !controller.isConnected) {
      return const Center(child: CircularProgressIndicator());
    }
    return _NavigationRemote(controller: controller, app: app);
  }
}

class _NavigationRemote extends StatelessWidget {
  const _NavigationRemote({required this.controller, required this.app});

  final RemoteController controller;
  final AppSnapshot? app;

  @override
  Widget build(BuildContext context) {
    final textInput = controller.textInputSnapshot;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        if (app?.sections.isNotEmpty == true)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final section in app!.sections)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_sectionTitle(section)),
                      selected: app!.selectedSection == section,
                      onSelected: (_) => controller.openSection(section),
                    ),
                  ),
              ],
            ),
          ),
        if (textInput != null) ...[
          const SizedBox(height: 20),
          _RemoteTextField(controller: controller, snapshot: textInput),
        ],
        const SizedBox(height: 28),
        Center(child: DirectionalPad(controller: controller)),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: controller.back,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: controller.activateMac,
                icon: const Icon(Icons.desktop_mac_rounded),
                label: const Text('Show Mac'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RemoteTextField extends StatefulWidget {
  const _RemoteTextField({required this.controller, required this.snapshot});

  final RemoteController controller;
  final TextInputSnapshot snapshot;

  @override
  State<_RemoteTextField> createState() => _RemoteTextFieldState();
}

class _RemoteTextFieldState extends State<_RemoteTextField> {
  late final TextEditingController textController;
  final focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    textController = TextEditingController(text: widget.snapshot.text);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => focusNode.requestFocus(),
    );
  }

  @override
  void didUpdateWidget(covariant _RemoteTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.snapshot.sessionId != oldWidget.snapshot.sessionId ||
        (widget.snapshot.text != textController.text &&
            widget.snapshot.text != oldWidget.snapshot.text)) {
      textController.value = TextEditingValue(
        text: widget.snapshot.text,
        selection: TextSelection.collapsed(offset: widget.snapshot.text.length),
      );
    }
  }

  @override
  void dispose() {
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: textController,
    focusNode: focusNode,
    maxLength: widget.snapshot.maximumLength,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search_rounded),
      hintText: 'Search on CineLark',
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      suffixIcon: IconButton(
        onPressed: widget.controller.cancelText,
        icon: const Icon(Icons.close_rounded),
      ),
    ),
    onChanged: widget.controller.updateText,
    onSubmitted: (_) => widget.controller.commitText(),
  );
}

class _LoginRemote extends StatefulWidget {
  const _LoginRemote({required this.controller});
  final RemoteController controller;

  @override
  State<_LoginRemote> createState() => _LoginRemoteState();
}

class _LoginRemoteState extends State<_LoginRemote> {
  final username = TextEditingController();
  final password = TextEditingController();
  final totp = TextEditingController();
  bool showTotp = false;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    totp.dispose();
    super.dispose();
  }

  void submit() {
    if (username.text.trim().isEmpty || password.text.isEmpty) return;
    widget.controller.submitCredentials(
      username: username.text.trim(),
      password: password.text,
      totpCode: showTotp ? totp.text : null,
    );
    password.clear();
    totp.clear();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 48, 28, 40),
    children: [
      const Icon(Icons.lock_person_rounded, size: 70),
      const SizedBox(height: 22),
      Text(
        'Sign in on your Mac',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      const Text(
        'Credentials are sent only to your paired CineLark Mac over the pinned connection.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 30),
      TextField(
        controller: username,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.username],
        decoration: const InputDecoration(labelText: 'Username'),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: password,
        obscureText: true,
        textInputAction: showTotp ? TextInputAction.next : TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        decoration: const InputDecoration(labelText: 'Password'),
        onSubmitted: (_) {
          if (!showTotp) submit();
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Use verification code'),
        value: showTotp,
        onChanged: (value) => setState(() => showTotp = value),
      ),
      if (showTotp)
        TextField(
          controller: totp,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(labelText: 'Verification Code'),
          onSubmitted: (_) => submit(),
        ),
      if (widget.controller.authenticationError != null) ...[
        const SizedBox(height: 14),
        const Text(
          'CineLark could not sign in. Check the credentials and try again.',
          style: TextStyle(color: Colors.redAccent),
        ),
      ],
      const SizedBox(height: 24),
      FilledButton(
        onPressed: widget.controller.isSubmittingLogin ? null : submit,
        child: widget.controller.isSubmittingLogin
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Sign In'),
      ),
    ],
  );
}

class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context) => const MaterialBanner(
    content: Text('Reconnecting to your Mac…'),
    leading: SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    actions: [SizedBox.shrink()],
  );
}

class _ErrorBanner extends StatefulWidget {
  const _ErrorBanner({required this.code, required this.onDismiss});

  final String code;
  final VoidCallback onDismiss;

  @override
  State<_ErrorBanner> createState() => _ErrorBannerState();
}

class _ErrorBannerState extends State<_ErrorBanner> {
  static const _displayDuration = Duration(seconds: 4);
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _scheduleDismissal();
  }

  @override
  void didUpdateWidget(_ErrorBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _scheduleDismissal();
    }
  }

  void _scheduleDismissal() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(_displayDuration, widget.onDismiss);
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text(_errorMessage(widget.code)),
    actions: [
      TextButton(onPressed: widget.onDismiss, child: const Text('Dismiss')),
    ],
  );
}

String _sectionTitle(String section) => switch (section) {
  'home' => 'Home',
  'movies' => 'Movies',
  'series' => 'Series',
  'favorites' => 'Favorites',
  'search' => 'Search',
  _ => section,
};

String _errorMessage(String code) => switch (code) {
  'staleRevision' => 'CineLark state changed. Controls were refreshed.',
  'invalidState' => 'That control is not available on the current screen.',
  'rateLimited' => 'Too many commands. Wait a moment and try again.',
  _ => 'CineLark could not complete the last command.',
};
