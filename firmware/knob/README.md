# HomeDeck knob — ESP32 firmware

A BLE peripheral that reports two things: that it was turned, and that it was pressed.

It knows nothing about lights, rooms, brightness or scenes. Those all live in the Flutter app,
which is why rearranging the house never means reflashing the board. The trade is deliberate:
the firmware is small enough to reason about completely, and the interesting decisions stay
where they can be changed in seconds and covered by tests.

## GATT contract

| | |
|---|---|
| Advertised name | `HomeDeck Knob` |
| Service | `4d1c1a00-8b6e-4f3a-9f2d-1c7a5e9b3d40` |
| Characteristic | `4d1c1a01-8b6e-4f3a-9f2d-1c7a5e9b3d40` (read, notify) |

Every notification is two bytes:

```
[0] event   0x01 = rotate, 0x02 = press
[1] delta   signed detents for a rotate, 0 for a press
```

Deltas rather than positions: a relative change cannot disagree with a light that was also
changed from the phone or the wall switch, where an absolute reading from a potentiometer
would fight whatever else touched the light.

## Wiring

The encoder is an EN11-HSM1BF20 — a bare component, not a breakout board, so it brings no
pull-up resistors of its own. The ESP32's internal pull-ups do that job, which is why every
input pin here is one that has them; GPIO 34–39 cannot pull up and would need external
resistors.

| Encoder pin | ESP32 |
|---|---|
| A (outer, encoder side) | GPIO 32 |
| C (centre, encoder side) | GND |
| B (outer, encoder side) | GPIO 33 |
| Switch (either pin) | GPIO 25 |
| Switch (other pin) | GND |

The onboard LED on GPIO 2 blinks while advertising and goes solid once a phone connects — the
only diagnostic left once the board is on a wall with no serial cable attached.

Confirm which side is which with a multimeter in continuity mode before wiring: the encoder's
three pins are one side, the switch's two the other.

## Build and flash

```
pio run                         # compile; needs no board attached
pio run --target upload         # flash over USB
pio device monitor              # watch the events it thinks it is sending
```

The USB serial chip is a CP2102; Windows needs Silicon Labs' VCP driver before a COM port
appears at all.

## Why a state table for the encoder

A detent is one full quadrature cycle, so counting raw edges would report four steps for every
click the hand feels. The transition table in `main.cpp` maps each pair of consecutive AB
readings to −1, 0 or +1, and whole detents are drained from the accumulator in the main loop.
Impossible transitions — both lines appearing to change at once, which is what a contact bounce
looks like — map to zero instead of inventing a step, so the knob does not creep when the
contacts are dirty.
