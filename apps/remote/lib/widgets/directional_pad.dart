import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/remote_controller.dart';

class DirectionalPad extends StatelessWidget {
  const DirectionalPad({super.key, required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 286,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xff171c27),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: _DirectionButton(
            icon: Icons.keyboard_arrow_up_rounded,
            onPressed: () => controller.move('up'),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _DirectionButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: () => controller.move('down'),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _DirectionButton(
            icon: Icons.keyboard_arrow_left_rounded,
            onPressed: () => controller.move('left'),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: _DirectionButton(
            icon: Icons.keyboard_arrow_right_rounded,
            onPressed: () => controller.move('right'),
          ),
        ),
        FilledButton.tonal(
          onPressed: () {
            HapticFeedback.mediumImpact();
            controller.select();
          },
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            fixedSize: const Size.square(104),
          ),
          child: const Text('OK', style: TextStyle(fontSize: 20)),
        ),
      ],
    ),
  );
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: () {
      HapticFeedback.selectionClick();
      onPressed();
    },
    icon: Icon(icon, size: 46),
    style: IconButton.styleFrom(fixedSize: const Size.square(88)),
  );
}
