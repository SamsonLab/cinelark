import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/remote_controller.dart';
import '../models/remote_protocol.dart';
import '../widgets/cinelark_mark.dart';

class DeviceSelectionScreen extends StatelessWidget {
  const DeviceSelectionScreen({super.key, required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CineLark R')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          const Center(child: CineLarkMark(size: 88)),
          const SizedBox(height: 20),
          Text(
            'Choose a Mac',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            controller.pairedMacs.isEmpty
                ? 'Add your first CineLark Mac to get started.'
                : 'Select a paired device to connect.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white60),
          ),
          const SizedBox(height: 28),
          for (final device in controller.pairedMacs) ...[
            _DeviceItem(controller: controller, device: device),
            const SizedBox(height: 10),
          ],
          Card(
            key: const ValueKey('add-device'),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              minTileHeight: 76,
              leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
              title: const Text(
                'Add New Device',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Scan a pairing code from CineLark for Mac'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => unawaited(controller.addDevice()),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DeviceItem extends StatelessWidget {
  const _DeviceItem({required this.controller, required this.device});

  final RemoteController controller;
  final PairedMac device;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('device-${device.serviceId}'),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      minTileHeight: 82,
      leading: CircleAvatar(
        radius: 26,
        child: Icon(_platformIcon(device.platform), size: 28),
      ),
      title: Text(
        device.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${device.host}:${device.port}'),
      trailing: PopupMenuButton<String>(
        tooltip: 'Device Actions',
        onSelected: (value) {
          if (value == 'forget') {
            unawaited(controller.removeDevice(device));
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'forget', child: Text('Forget Device')),
        ],
      ),
      onTap: () => unawaited(controller.selectDevice(device)),
    ),
  );
}

IconData _platformIcon(HostPlatform platform) => switch (platform) {
  HostPlatform.macOS => Icons.apple_rounded,
  HostPlatform.windows => Icons.window_rounded,
  HostPlatform.linux => Icons.terminal_rounded,
  HostPlatform.unknown => Icons.computer_rounded,
};
