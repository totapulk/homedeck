// HomeDeck knob — a deliberately ignorant BLE peripheral.
//
// It reports which control moved and how far. It does not know what a light is, which room it
// is in, or that one of these knobs is meant for a vacuum cleaner. Everything that could change
// with the product lives in the app, so this firmware should never need reflashing because
// someone rearranged their house or changed their mind about what a knob is for.
//
// Adding a third control is one line in kKnobs below.

#include <Arduino.h>
#include <NimBLEDevice.h>

namespace {

constexpr char kDeviceName[] = "HomeDeck Knob";
constexpr char kServiceUuid[] = "4d1c1a00-8b6e-4f3a-9f2d-1c7a5e9b3d40";
constexpr char kEventsUuid[] = "4d1c1a01-8b6e-4f3a-9f2d-1c7a5e9b3d40";

// Payload is three bytes: [control, event, signed delta]. The control index says which knob
// moved and nothing about what it means — naming one of them "the vacuum knob" here is exactly
// the knowledge this firmware must not hold.
constexpr uint8_t kEventRotate = 0x01;
constexpr uint8_t kEventPress = 0x02;

struct KnobPins {
  uint8_t a;
  uint8_t b;
  uint8_t button;
};

// Pins chosen from the range with usable internal pull-ups: the encoders are bare components
// with no resistors of their own. GPIO 34-39 cannot pull up, and GPIO 12 selects the flash
// voltage at boot — held high, the board will not start.
constexpr KnobPins kKnobs[] = {
    {.a = 32, .b = 33, .button = 25},
    {.a = 26, .b = 27, .button = 14},
};
constexpr size_t kKnobCount = sizeof(kKnobs) / sizeof(kKnobs[0]);

constexpr uint8_t kPinLed = 2;

// A detent is one full quadrature cycle. Counting raw transitions would report four steps for
// every click the hand feels.
constexpr int16_t kTransitionsPerDetent = 4;
constexpr uint32_t kButtonDebounceMs = 30;
constexpr uint32_t kAdvertisingBlinkMs = 500;

// Gray-code transition table: index is the previous two bits followed by the current two.
// Impossible transitions — both lines changing at once, which is what a contact bounce looks
// like — contribute zero rather than a phantom step.
constexpr int8_t kTransition[16] = {
    0,  -1, +1, 0,
    +1, 0,  0,  -1,
    -1, 0,  0,  +1,
    0,  +1, -1, 0,
};

struct Knob {
  KnobPins pins;
  uint8_t index;

  volatile int16_t transitions;
  volatile uint8_t previousState;

  bool buttonDebounced;
  bool buttonLastReading;
  uint32_t buttonLastChangeMs;
};

Knob gKnobs[kKnobCount];
portMUX_TYPE gCounterMux = portMUX_INITIALIZER_UNLOCKED;

NimBLECharacteristic* gEvents = nullptr;
volatile bool gConnected = false;

uint8_t readEncoderState(const Knob& knob) {
  return static_cast<uint8_t>((digitalRead(knob.pins.a) << 1) | digitalRead(knob.pins.b));
}

void IRAM_ATTR onEncoderEdge(void* arg) {
  Knob* knob = static_cast<Knob*>(arg);
  const uint8_t state =
      static_cast<uint8_t>((digitalRead(knob->pins.a) << 1) | digitalRead(knob->pins.b));

  portENTER_CRITICAL_ISR(&gCounterMux);
  knob->transitions += kTransition[(knob->previousState << 2) | state];
  knob->previousState = state;
  portEXIT_CRITICAL_ISR(&gCounterMux);
}

class KnobServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* /*server*/, NimBLEConnInfo& /*info*/) override {
    gConnected = true;
    Serial.println("central connected");
  }

  void onDisconnect(NimBLEServer* /*server*/, NimBLEConnInfo& /*info*/, int reason) override {
    gConnected = false;
    Serial.printf("central disconnected (reason %d), advertising again\n", reason);
    NimBLEDevice::startAdvertising();
  }
};

void notifyEvent(uint8_t control, uint8_t event, int8_t delta) {
  if (!gConnected || gEvents == nullptr) {
    return;
  }

  const uint8_t payload[3] = {control, event, static_cast<uint8_t>(delta)};
  gEvents->setValue(payload, sizeof(payload));
  gEvents->notify();
}

/// Drains whole detents from the interrupt counter, leaving any partial one behind so a slow
/// turn across the boundary is not lost.
int16_t takeDetents(Knob& knob) {
  int16_t detents = 0;

  portENTER_CRITICAL(&gCounterMux);
  while (knob.transitions >= kTransitionsPerDetent) {
    knob.transitions -= kTransitionsPerDetent;
    ++detents;
  }
  while (knob.transitions <= -kTransitionsPerDetent) {
    knob.transitions += kTransitionsPerDetent;
    --detents;
  }
  portEXIT_CRITICAL(&gCounterMux);

  return detents;
}

void pollButton(Knob& knob, uint32_t now) {
  const bool reading = digitalRead(knob.pins.button) == LOW;  // pulled up, so pressed reads low
  if (reading != knob.buttonLastReading) {
    knob.buttonLastReading = reading;
    knob.buttonLastChangeMs = now;
  }

  if (now - knob.buttonLastChangeMs >= kButtonDebounceMs && reading != knob.buttonDebounced) {
    knob.buttonDebounced = reading;
    if (knob.buttonDebounced) {
      Serial.printf("knob %u press\n", knob.index);
      notifyEvent(knob.index, kEventPress, 0);
    }
  }
}

#if KNOB_PIN_DEBUG
/// Prints the raw level of every input whenever one of them changes.
///
/// This answers the only question worth asking when a freshly wired knob does nothing: are the
/// pins moving at all? If they never change, the fault is in the wiring and no amount of reading
/// the decoder will help. If they do change, the wiring is fine and the decoder is the suspect.
void reportRawPins() {
  static uint8_t previous[kKnobCount] = {};
  static bool reported = false;

  for (size_t i = 0; i < kKnobCount; ++i) {
    const Knob& knob = gKnobs[i];
    const uint8_t raw = static_cast<uint8_t>((digitalRead(knob.pins.a) << 2) |
                                            (digitalRead(knob.pins.b) << 1) |
                                            digitalRead(knob.pins.button));

    if (reported && raw == previous[i]) {
      continue;
    }

    previous[i] = raw;
    Serial.printf("knob %u raw  A=%d B=%d SW=%d\n", knob.index, (raw >> 2) & 1, (raw >> 1) & 1,
                  raw & 1);
  }

  reported = true;
}
#endif

}  // namespace

void setup() {
  Serial.begin(115200);
  pinMode(kPinLed, OUTPUT);

  for (size_t i = 0; i < kKnobCount; ++i) {
    Knob& knob = gKnobs[i];
    knob.pins = kKnobs[i];
    knob.index = static_cast<uint8_t>(i);
    knob.transitions = 0;
    knob.buttonDebounced = false;
    knob.buttonLastReading = false;
    knob.buttonLastChangeMs = 0;

    pinMode(knob.pins.a, INPUT_PULLUP);
    pinMode(knob.pins.b, INPUT_PULLUP);
    pinMode(knob.pins.button, INPUT_PULLUP);

    knob.previousState = readEncoderState(knob);
    attachInterruptArg(digitalPinToInterrupt(knob.pins.a), onEncoderEdge, &knob, CHANGE);
    attachInterruptArg(digitalPinToInterrupt(knob.pins.b), onEncoderEdge, &knob, CHANGE);
  }

  NimBLEDevice::init(kDeviceName);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new KnobServerCallbacks());

  NimBLEService* service = server->createService(kServiceUuid);
  gEvents = service->createCharacteristic(
      kEventsUuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(kServiceUuid);

  // An advertisement is 31 bytes and a 128-bit service UUID claims 18 of them, which leaves no
  // room for the name. The name goes in the scan response instead — a central that wants it
  // asks for it separately, and one filtering by service UUID never needs it at all.
  NimBLEAdvertisementData scanResponse;
  scanResponse.setName(kDeviceName);
  advertising->setScanResponseData(scanResponse);
  advertising->enableScanResponse(true);

  NimBLEDevice::startAdvertising();

  Serial.printf("advertising as %s with %u control(s)\n", kDeviceName, kKnobCount);
}

void loop() {
  const uint32_t now = millis();

#if KNOB_PIN_DEBUG
  reportRawPins();
#endif

  for (size_t i = 0; i < kKnobCount; ++i) {
    Knob& knob = gKnobs[i];

    if (const int16_t detents = takeDetents(knob); detents != 0) {
      const int8_t delta = static_cast<int8_t>(constrain(detents, -127, 127));
      Serial.printf("knob %u rotate %d\n", knob.index, delta);
      notifyEvent(knob.index, kEventRotate, delta);
    }

    pollButton(knob, now);
  }

  // Blinking means looking for a phone, solid means connected. The one diagnostic available
  // when the board is on a wall with no serial cable attached.
  digitalWrite(kPinLed, gConnected ? HIGH : ((now / kAdvertisingBlinkMs) % 2));

  delay(2);
}
