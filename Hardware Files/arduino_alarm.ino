const int FSR_PINS[4] = {A0, A1, A2, A3};
const int BUZZER_PIN  = 8;

bool alarmActive      = false;
bool forceAlarmActive = false;

void setup() {
  Serial.begin(9600);
  Serial1.begin(9600);
  pinMode(BUZZER_PIN, OUTPUT);
  noTone(BUZZER_PIN);
  Serial.println("Arduino ready. Waiting for ESP32 command...");
}

void loop() {
  // ── 1. Check for commands from ESP32 ──────────────────
  if (Serial1.available()) {
    String msg = Serial1.readStringUntil('\n');
    msg.trim();

    if (msg == "ALARM_START") {
      alarmActive      = true;
      forceAlarmActive = false;
      Serial.println(">>> ALARM_START received. Sensors are LIVE!");
    }
    else if (msg == "ALARM_STOP") {
      alarmActive      = false;
      forceAlarmActive = false;
      noTone(BUZZER_PIN);
      Serial.println(">>> ALARM_STOP received. System deactivated.");
    }
    else if (msg == "TEST_ALARM") {
      Serial.println(">>> TEST_ALARM received. Testing buzzer...");
      tone(BUZZER_PIN, 1000);
      delay(2000);
      if (!forceAlarmActive) noTone(BUZZER_PIN);
      Serial.println(">>> Test complete.");
    }
    else if (msg == "MANUAL_NOISE") {
      Serial.println(">>> MANUAL ALARM received.");
      forceAlarmActive = true;
      alarmActive      = true;  // ensure FSR loop runs
      tone(BUZZER_PIN, 1000);
    }
    else if (msg == "MANUAL_STOP") {
      Serial.println(">>> ALARM KILL received. Stopping everything.");
      alarmActive      = false;
      forceAlarmActive = false;
      noTone(BUZZER_PIN);
    }
  }

 // ── 2. Read & Send Sensors ────────────────────────────
  if (alarmActive) {
    int readings[4];
    bool allZero = true;

    for (int i = 0; i < 4; i++) {
      readings[i] = analogRead(FSR_PINS[i]);
      if (readings[i] > 0) allZero = false;
    }

    String dataMsg = "FSR:" + String(readings[0]) + "," +
                               String(readings[1]) + "," +
                               String(readings[2]) + "," +
                               String(readings[3]);
    Serial1.println(dataMsg);
    Serial.println("Sent: " + dataMsg);

    if (forceAlarmActive) {
      if (allZero) {
        noTone(BUZZER_PIN);
        Serial.println(">>> All FSRs zero, waiting for pressure...");
      } else {
        tone(BUZZER_PIN, 1000);  // they got back in, buzz again
      }
    } 
  }
  delay(100);
}
