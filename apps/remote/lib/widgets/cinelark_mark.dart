import 'package:flutter/material.dart';

class CineLarkMark extends StatelessWidget {
  const CineLarkMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/maskAppIcon.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    excludeFromSemantics: true,
  );
}
