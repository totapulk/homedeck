# HomeDeck knob — ESP32 firmware

A BLE peripheral that reports two things: that a control was turned, and that a control was
pressed.

It knows nothing about lights, rooms, brightness, scenes or vacuum cleaners. Those all live in
the Flutter app, which is why rearranging the house never means reflashing the board — and why
deciding that the second knob now picks a cleaning mode instead of a light is a change to one
Dart class. The trade is deliberate: the firmware stays small enough to reason about completely,
and the decisions that change stay where they can be changed in seconds and covered by tests.

Two controls are wired today. Adding a third is one line in `kKnobs`.

## GATT contract

| | |
|---|---|
| Advertised name | `HomeDeck Knob` |
| Service | `4d1c1a00-8b6e-4f3a-9f2d-1c7a5e9b3d40` |
| Characteristic | `4d1c1a01-8b6e-4f3a-9f2d-1c7a5e9b3d40` (read, notify) |

Every notification is three bytes:

```
[0] control  which physical control moved: 0, 1, ...
[1] event    0x01 = rotate, 0x02 = press
[2] delta    signed detents for a rotate, 0 for a press
```

The control index says *which* knob moved and nothing about what it means. Calling one of them
"the vacuum knob" here is precisely the knowledge this firmware must not hold; the app owns
that mapping, and changing it costs a reflash of nothing.

Deltas rather than positions: a relative change cannot disagree with a light that was also
changed from the phone or the wall switch, where an absolute reading from a potentiometer
would fight whatever else touched the light.

## Wiring

The encoders are EN11-HSM1BF20 — bare components, not breakout boards, so they bring no pull-up
resistors of their own. The ESP32's internal pull-ups do that job, which is why every input pin
here is one that has them. GPIO 34–39 cannot pull up, and GPIO 12 selects the flash voltage at
boot: held high, the board will not start.

| | Control 0 | Control 1 |
|---|---|---|
| A (outer, encoder side) | GPIO 32 | GPIO 26 |
| B (other outer, encoder side) | GPIO 33 | GPIO 27 |
| C (centre, encoder side) | GND | GND |
| Switch (either pin) | GPIO 25 | GPIO 14 |
| Switch (other pin) | GND | GND |

No meter is needed to tell the two groups apart: an encoder's three pins are on one side of the
body and its switch's two are on the other. Nor does it matter which outer pin is A and which is
B — swapping them reverses that knob's direction of travel and nothing else.

The connections are made with female-to-female jumpers straight onto the board's header, with no
breadboard involved. The encoders' mounting lugs are meant for a PCB and do not line up with
breadboard holes, and the ESP32 has several ground pins, which was the only thing a breadboard's
ground rail was needed for. The same connections carry over unchanged when the encoders move to
a panel-mounted enclosure.

Each encoder gets its own interrupt-handler argument rather than its own handler function, so
the number of controls is data rather than code.

The onboard LED on GPIO 2 blinks while advertising and goes solid once a phone connects — the
only diagnostic left once the board is on a wall with no serial cable attached.

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
