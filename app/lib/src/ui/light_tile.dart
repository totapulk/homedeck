import 'package:flutter/material.dart';

import '../models/light.dart';
import '../models/light_command.dart';
import '../state/light_store.dart';

class LightTile extends StatefulWidget {
  const LightTile({super.key, required this.light, this.isSelected = false});

  final Light light;

  /// Whether a physical controller acts on this light.
  final bool isSelected;

  @override
  State<LightTile> createState() => _LightTileState();
}

class _LightTileState extends State<LightTile> {
  /// Set only while a finger is on the slider. The store holds the truth; this holds the
  /// gesture, so dragging stays smooth without a request per pixel.
  double? _dragging;

  double get _brightness => _dragging ?? widget.light.brightness.toDouble();

  Future<void> _send(LightCommand command) async {
    final store = LightScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final failure = await store.apply(widget.light, command);
    if (failure == null || !mounted) return;

    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(failure)));
  }

  @override
  Widget build(BuildContext context) {
    final light = widget.light;
    final scheme = Theme.of(context).colorScheme;
    final active = light.isReachable && light.isOn;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: widget.isSelected
            ? BorderSide(color: scheme.primary.withValues(alpha: 0.7), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => LightScope.of(context).select(light.id),
        borderRadius: BorderRadius.circular(18),
        child: Opacity(
          opacity: light.isReachable ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    _Bulb(active: active, brightness: light.brightness),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  light.name,
                                  style: Theme.of(context).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.isSelected) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: 'The knob controls this light',
                                  child: Icon(
                                    Icons.tune,
                                    size: 14,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _status(light),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: light.isReachable
                                      ? scheme.onSurfaceVariant
                                      : scheme.error,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: light.isOn,
                      onChanged: light.isReachable
                          ? (value) => _send(LightCommand(isOn: value))
                          : null,
                    ),
                  ],
                ),
                Slider(
                  value: _brightness.clamp(0, 100),
                  max: 100,
                  divisions: 20,
                  label: '${_brightness.round()}%',
                  onChanged: light.isReachable
                      ? (value) => setState(() => _dragging = value)
                      : null,
                  onChangeEnd: (value) {
                    _send(LightCommand(brightness: value.round()));
                    setState(() => _dragging = null);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _status(Light light) {
    if (!light.isReachable) return 'Not responding';
    if (!light.isOn) return 'Off';

    final temp = light.colorTempK;
    return temp == null ? '${light.brightness}%' : '${light.brightness}% · ${temp}K';
  }
}

class _Bulb extends StatelessWidget {
  const _Bulb({required this.active, required this.brightness});

  final bool active;
  final int brightness;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // The halo tracks brightness, so a glance across the room reads as a dimmer level
    // rather than as a list of identical icons.
    final glow = active ? (0.25 + brightness / 100 * 0.75) : 0.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(
          scheme.surfaceContainerHighest,
          scheme.primary,
          glow * 0.9,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: glow * 0.45),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Icon(
        active ? Icons.lightbulb : Icons.lightbulb_outline,
        size: 22,
        color: active ? const Color(0xFF2A1D06) : scheme.onSurfaceVariant,
      ),
    );
  }
}
