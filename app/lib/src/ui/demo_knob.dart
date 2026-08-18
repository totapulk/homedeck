import 'package:flutter/material.dart';

import '../controller/controller_input.dart';

/// An on-screen stand-in for the physical knob.
///
/// It feeds the same [MockControllerInput] the tests use, so pressing these buttons exercises
/// the real event pipeline — binding, intent, request, confirmed state — rather than reaching
/// into the store behind its back. When the ESP32 arrives it replaces the input and nothing
/// else changes.
class DemoKnob extends StatelessWidget {
  const DemoKnob({super.key, required this.input, required this.child});

  final MockControllerInput input;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        child,
        Positioned(
          right: 16,
          bottom: 16,
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(28),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => input.rotate(-1),
                    icon: const Icon(Icons.rotate_left),
                    tooltip: 'Turn anticlockwise',
                  ),
                  IconButton(
                    onPressed: input.press,
                    icon: const Icon(Icons.radio_button_checked),
                    tooltip: 'Press the knob',
                  ),
                  IconButton(
                    onPressed: () => input.rotate(1),
                    icon: const Icon(Icons.rotate_right),
                    tooltip: 'Turn clockwise',
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
