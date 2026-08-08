// Blinks the on-board LED and prints over USB serial.
// Exercises GPIO, the core timer (delay) and USB CDC in one sketch.

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(115200);
}

void loop() {
  digitalWrite(LED_BUILTIN, HIGH);
  delay(500);
  digitalWrite(LED_BUILTIN, LOW);
  delay(500);
  Serial.println("flinduino native arm64");
}
