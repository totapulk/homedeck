// HomeDeck knob — a deliberately ignorant BLE peripheral.
//
// It reports that it was turned or pressed. It does not know what a light is, which room it is
// in, or what brightness means. Everything that could change with the product lives in the app,
// so this firmware should never need reflashing because someone rearranged their house.

#include <Arduino.h>
#include <NimBLEDevice.h>

namespace {

constexpr char kDeviceName[] = "HomeDeck Knob";
constexpr char kServiceUuid[] = "4d1c1a00-8b6e-4f3a-9f2d-1c7a5e9b3d40";
constexpr char kEventsUuid[] = "4d1c1a01-8b6e-4f3a-9f2d-1c7a5e9b3d40";

// Payload is two bytes: [event, signed delta]. Small enough to fit any connection interval,
// and readable in a packet capture without a decoder ring.
constexpr uint8_t kEventRotate = 0x01;
constexpr uint8_t kEventPress = 0x02;

// Pins chosen from the range that has usable internal pull-ups. GPIO 34-39 cannot pull up, and
// the encoder is a bare component with no resistors of its own.
constexpr uint8_t kPinEncoderA = 32;
constexpr uint8_t kPinEncoderB = 33;
constexpr uint8_t kPinButton = 25;
constexpr uint8_t kPinLed = 2;

// A detent is one full quadrature cycle. Counting raw transitions would report four steps for
// every click the hand feels.
constexpr int16_t kTransitionsPerDetent = 4;
constexpr uint32_t kButtonDebounceMs = 30;
constexpr uint32_t kAdvertisingBlinkMs = 500;

// Gray-code transition table: index is the previous two bits followed by the current two.
// Impossible transitions — both lines changing at once, which only happens on a bounce —
// contribute zero rather than a phantom step.
constexpr int8_t kTransition[16] = {
    0, -1, +1, 0,
    +1, 0, 0, -1,
    -1, 0, 0, +1,
    0, +1, -1, 0,
};

portMUX_TYPE gCounterMux = portMUX_INITIALIZER_UNLOCKED;
volatile int16_t gTransitions = 0;
volatile uint8_t gPreviousState = 0;

NimBLECharacteristic* gEvents = nullptr;
volatile bool gConnected = false;

void IRAM_ATTR onEncoderEdge() {
  const uint8_t state =
      static_cast<uint8_t>((digitalRead(kPinEncoderA) << 1) | digitalRead(kPinEncoderB));

  portENTER_CRITICAL_ISR(&gCounterMux);
  gTransitions += kTransition[(gPreviousState << 2) | state];
  gPreviousState = state;
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

void notifyEvent(uint8_t event, int8_t delta) {
  if (!gConnected || gEvents == nullptr) {
    return;
  }

  const uint8_t payload[2] = {event, static_cast<uint8_t>(delta)};
  gEvents->setValue(payload, sizeof(payload));
  gEvents->notify();
}

/// Drains whole detents from the interrupt counter, leaving any partial one behind so a slow
/// turn across the boundary is not lost.
int16_t takeDetents() {
  int16_t detents = 0;

  portENTER_CRITICAL(&gCounterMux);
  while (gTransitions >= kTransitionsPerDetent) {
    gTransitions -= kTransitionsPerDetent;
    ++detents;
  }
  while (gTransitions <= -kTransitionsPerDetent) {
    gTransitions += kTransitionsPerDetent;
    --detents;
  }
  portEXIT_CRITICAL(&gCounterMux);

  return detents;
}

void pollButton(uint32_t now) {
  static bool debounced = false;
  static bool lastReading = false;
  static uint32_t lastChangeMs = 0;

  const bool reading = digitalRead(kPinButton) == LOW;  // pulled up, so pressed reads low
  if (reading != lastReading) {
    lastReading = reading;
    lastChangeMs = now;
  }

  if (now - lastChangeMs >= kButtonDebounceMs && reading != debounced) {
    debounced = reading;
    if (debounced) {
      Serial.println("press");
      notifyEvent(kEventPress, 0);
    }
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);

  pinMode(kPinEncoderA, INPUT_PULLUP);
  pinMode(kPinEncoderB, INPUT_PULLUP);
  pinMode(kPinButton, INPUT_PULLUP);
  pinMode(kPinLed, OUTPUT);

  gPreviousState =
      static_cast<uint8_t>((digitalRead(kPinEncoderA) << 1) | digitalRead(kPinEncoderB));
  attachInterrupt(digitalPinToInterrupt(kPinEncoderA), onEncoderEdge, CHANGE);
  attachInterrupt(digitalPinToInterrupt(kPinEncoderB), onEncoderEdge, CHANGE);

  NimBLEDevice::init(kDeviceName);

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new KnobServerCallbacks());

  NimBLEService* service = server->createService(kServiceUuid);
  gEvents = service->createCharacteristic(
      kEventsUuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(kServiceUuid);
  advertising->setName(kDeviceName);
  NimBLEDevice::startAdvertising();

  Serial.println("advertising as " + String(kDeviceName));
}

void loop() {
  const uint32_t now = millis();

  if (const int16_t detents = takeDetents(); detents != 0) {
    const int8_t delta = static_cast<int8_t>(constrain(detents, -127, 127));
    Serial.printf("rotate %d\n", delta);
    notifyEvent(kEventRotate, delta);
  }

  pollButton(now);

  // Blinking means looking for a phone, solid means connected. The one diagnostic available
  // when the board is on a wall with no serial cable attached.
  digitalWrite(kPinLed, gConnected ? HIGH : ((now / kAdvertisingBlinkMs) % 2));

  delay(2);
}
