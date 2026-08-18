import 'package:flutter/material.dart';

import '../controller/controller_input.dart';

/// An on-screen stand-in for the physical knobs.
///
/// It feeds the same [MockControllerInput] the tests use, so pressing these buttons exercises
/// the real event pipeline — binding, intent, request, confirmed state — rather than reaching
/// into the store behind its back. What each control does is decided in ControllerBinding, so
/// this pad deliberately labels them by number and not by purpose.
class DemoKnob extends StatelessWidget {
  const DemoKnob({
    super.key,
    required this.input,
    required this.child,
    this.controls = 2,
  });

  final MockControllerInput input;
  final int controls;
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
            borderRadius: BorderRadius.circular(20),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var control = 0; control < controls; control++)
                    _Pad(input: input, control: control),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad({required this.input, required this.control});

  final MockControllerInput input;
  final int control;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$control',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        IconButton(
          onPressed: () => input.rotate(-1, control: control),
          icon: const Icon(Icons.rotate_left),
          tooltip: 'Turn control $control anticlockwise',
        ),
        IconButton(
          onPressed: () => input.press(control: control),
          icon: const Icon(Icons.radio_button_checked),
          tooltip: 'Press control $control',
        ),
        IconButton(
          onPressed: () => input.rotate(1, control: control),
          icon: const Icon(Icons.rotate_right),
          tooltip: 'Turn control $control clockwise',
        ),
      ],
    );
  }
}
