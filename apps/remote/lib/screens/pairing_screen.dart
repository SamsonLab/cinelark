import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../controller/remote_controller.dart';
import '../widgets/cinelark_mark.dart';
import 'pairing_scan_gate.dart';

typedef PairingScannerBuilder =
    Widget Function(
      MobileScannerController controller,
      void Function(BarcodeCapture capture) onDetect,
    );

class PairingScreen extends StatefulWidget {
  const PairingScreen({
    super.key,
    required this.controller,
    this.scannerBuilder,
  });

  final RemoteController controller;

  @visibleForTesting
  final PairingScannerBuilder? scannerBuilder;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 750,
  );
  final scanGate = PairingScanGate();

  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }

  Future<void> handleCapture(BarcodeCapture capture) async {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || !scanGate.tryBeginCapture()) return;
    debugPrint('[remote] qr_detected');
    await scanner.stop();
    debugPrint('[remote] scanner_stopped_for_pairing');
    try {
      await widget.controller.pair(raw);
    } on FormatException catch (error) {
      debugPrint('[remote] qr_rejected reason=${error.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
      setState(scanGate.reset);
      await scanner.start();
    }
  }

  Future<void> scanAgain() async {
    debugPrint('[remote] retry_requested');
    await widget.controller.forget();
    if (!mounted) return;
    setState(scanGate.reset);
    // The scanner remounts after the failed view and starts itself. Starting it
    // here races its native view initialization and can leave the camera dark.
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.controller.phase;
    if (phase == RemoteConnectionPhase.connecting) {
      return const _PairingProgress(
        icon: Icons.lock_outline_rounded,
        title: 'Securing connection…',
        message: 'Verifying the Mac certificate from the QR code.',
      );
    }
    if (phase == RemoteConnectionPhase.awaitingApproval) {
      return const _PairingProgress(
        icon: Icons.phonelink_lock_rounded,
        title: 'Approve on your Mac',
        message: 'CineLark is waiting for you to approve this phone.',
      );
    }
    if (phase == RemoteConnectionPhase.failed) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_off_rounded, size: 72),
                  const SizedBox(height: 24),
                  Text(
                    'Pairing failed',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Scan the code again. If it has expired, reopen Remote on '
                    'the Mac to generate a new one.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: scanAgain,
                    child: const Text('Scan Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          widget.scannerBuilder?.call(scanner, handleCapture) ??
              MobileScanner(controller: scanner, onDetect: handleCapture),
          ColoredBox(color: Colors.black.withValues(alpha: 0.32)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const CineLarkMark(size: 64),
                  const SizedBox(height: 8),
                  Text(
                    'CineLark Remote',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 246,
                    height: 246,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Open Remote on CineLark for Mac\nand scan its pairing code',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingProgress extends StatelessWidget {
  const _PairingProgress({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72),
              const SizedBox(height: 28),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 28),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    ),
  );
}
