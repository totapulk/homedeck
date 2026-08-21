import 'package:flutter/material.dart';

import '../models/light_command.dart';
import '../models/light_group.dart';
import '../state/light_store.dart';

/// One lamp on screen — which may be one bulb, or several sharing a fixture.
///
/// Nothing here knows the difference beyond the label: a group of one behaves exactly like a
/// group of three, so the switch, the slider and the selection have no special cases.
class LightTile extends StatefulWidget {
  const LightTile({super.key, required this.group, this.isSelected = false});

  final LightGroup group;

  /// Whether the knob would move this lamp.
  final bool isSelected;

  @override
  State<LightTile> createState() => _LightTileState();
}

class _LightTileState extends State<LightTile> {
  /// Set only while a finger is on the slider. The store holds the truth; this holds the
  /// gesture, so dragging stays smooth without a request per pixel.
  double? _dragging;

  double get _brightness => _dragging ?? widget.group.brightness.toDouble();

  Future<void> _send(LightCommand command) async {
    final store = LightScope.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final failure = await store.applyToAll(widget.group.lights, command);
    if (failure == null || !mounted) return;

    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(failure)));
  }

  void _select() {
    final store = LightScope.of(context);
    final group = widget.group;

    if (group.fixture case final fixture?) {
      store.selectFixture(fixture);
    } else {
      store.selectLight(group.lights.first.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final scheme = Theme.of(context).colorScheme;
    final active = group.isReachable && group.isOn;

    return Card(
      // Every lamp the knob would move is outlined, so "what am I about to change" is answered
      // by looking rather than by remembering. With the whole home selected that is every card,
      // which is why the outline is quiet rather than loud.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: widget.isSelected
            ? BorderSide(color: scheme.primary.withValues(alpha: 0.45), width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: _select,
        borderRadius: BorderRadius.circular(18),
        child: Opacity(
          opacity: group.isReachable ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    _Bulb(active: active, brightness: group.brightness),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _status(group),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: group.isReachable
                                      ? scheme.onSurfaceVariant
                                      : scheme.error,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: group.isOn,
                      onChanged: group.isReachable
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
                  onChanged: group.isReachable
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

  static String _status(LightGroup group) {
    if (!group.isReachable) return 'Not responding';

    // A fixture says how many bulbs it is made of, because that is the thing a person cannot
    // tell from the outside and occasionally needs to know.
    final prefix = group.isFixture ? '${group.lights.length} bulbs · ' : '';
    if (!group.isOn) return '${prefix}Off';

    final temp = group.colorTempK;
    return temp == null
        ? '$prefix${group.brightness}%'
        : '$prefix${group.brightness}% · ${temp}K';
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
