#include <BLEDevice.h>

#include <BLEServer.h>

#include <BLEUtils.h>

#include <BLE2902.h>


HardwareSerial ArduinoSerial(2); // RX=GPIO16, TX=GPIO17


// BLE Variables

BLEServer *pServer = NULL;

BLECharacteristic *pTxCharacteristic;

bool deviceConnected = false;

bool oldDeviceConnected = false;

String incomingCmd = "";


// Standard UART Service UUIDs

#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"

#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"


// Timer Variables

bool isCountingDown = false;

unsigned long timerStartMs = 0;

const unsigned long DELAY_MS = 100; // 20 seconds


// ── BLE Server Callbacks ──

class MyServerCallbacks: public BLEServerCallbacks {

    void onConnect(BLEServer* pServer) { deviceConnected = true; }

    void onDisconnect(BLEServer* pServer) { deviceConnected = false; }

};


// ── BLE RX Callbacks ──

class MyCallbacks: public BLECharacteristicCallbacks {

    void onWrite(BLECharacteristic *pCharacteristic) {

      String rxValue = pCharacteristic->getValue();

      if (rxValue.length() > 0) {

        rxValue.trim();

        incomingCmd = rxValue;

      }

    }

};


// ── Helper Function to Send Text to Phone ──

void sendToPhone(String message) {

  if (deviceConnected) {

    message += "\n";

    pTxCharacteristic->setValue(message.c_str());

    pTxCharacteristic->notify();

  }

}


void setup() {

  Serial.begin(115200);

  ArduinoSerial.begin(9600, SERIAL_8N1, 16, 17);


  BLEDevice::init("Eveil");

  pServer = BLEDevice::createServer();

  pServer->setCallbacks(new MyServerCallbacks());


  BLEService *pService = pServer->createService(SERVICE_UUID);


  pTxCharacteristic = pService->createCharacteristic(

                        CHARACTERISTIC_UUID_TX,

                        BLECharacteristic::PROPERTY_NOTIFY

                      );

  pTxCharacteristic->addDescriptor(new BLE2902());


  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(

                                           CHARACTERISTIC_UUID_RX,

                                           BLECharacteristic::PROPERTY_WRITE

                                         );

  pRxCharacteristic->setCallbacks(new MyCallbacks());


  pService->start();

  pServer->getAdvertising()->start();


  Serial.println("ESP32 BLE Ready. Waiting for iOS connection...");

}


void loop() {

  //  Handle BLE Disconnect/Reconnect

  if (!deviceConnected && oldDeviceConnected) {

    delay(500);

    pServer->startAdvertising();

    Serial.println("Phone disconnected. Restarting advertising...");

    oldDeviceConnected = deviceConnected;

  }

  if (deviceConnected && !oldDeviceConnected) {

    oldDeviceConnected = deviceConnected;

    Serial.println("Phone Connected via BLE!");

    sendToPhone("Connected to Eveil ESP32!");

  }


  // Listen for Phone Commands

  if (incomingCmd.length() > 0) {


    // ARM — start the countdown

    if (incomingCmd == "ARM" && !isCountingDown) {

      Serial.println("'ARM' received. Starting countdown...");

      sendToPhone("Countdown started (" + String(DELAY_MS / 1000) + "s)...");

      isCountingDown = true;

      timerStartMs = millis();

    }


    // STOP — disarm everything

    else if (incomingCmd == "STOP") {

      Serial.println("'STOP' received. Disarming.");

      sendToPhone("Alarm deactivated.");

      isCountingDown = false;

      ArduinoSerial.println("ALARM_STOP");

    }


    // TEST ALARM — test the buzzer on Arduino

    else if (incomingCmd == "TEST ALARM") {

      Serial.println("'TEST ALARM' received. Forwarding to Arduino...");

      sendToPhone("Testing buzzer for 2 seconds...");

      ArduinoSerial.println("TEST_ALARM");

    }


    // THRESHOLD:xxx — change FSR threshold on Arduino

    // Example: send "THRESHOLD:500" from the app

    else if (incomingCmd.startsWith("THRESHOLD:")) {

      String val = incomingCmd.substring(10);

      ArduinoSerial.println(incomingCmd);

      sendToPhone("Threshold updated to: " + val);

      Serial.println("Threshold forwarded: " + val);

    }


    // MANUAL_NOISE — manually turn buzzer on via app

    else if (incomingCmd == "FORCE ALARM") {

      Serial.println("'MANUAL_NOISE' received. Forwarding to Arduino...");

      sendToPhone("Buzzer manually activated.");

      ArduinoSerial.println("MANUAL_NOISE");

      isCountingDown = false;

    }


    // MANUAL_STOP — manually turn buzzer off via app

    else if (incomingCmd == "ALARM KILL") {

      Serial.println("'MANUAL_STOP' received. Forwarding to Arduino...");

      sendToPhone("Buzzer manually stopped.");

      ArduinoSerial.println("MANUAL_STOP");

      isCountingDown = false;

    }


    else {

      sendToPhone("Unknown command: " + incomingCmd);

      Serial.println("Unknown command: " + incomingCmd);

    }


    incomingCmd = ""; // Always clear at the bottom

  }


  // Handle the countdown 

  if (isCountingDown) {

    unsigned long elapsed = millis() - timerStartMs;

    unsigned long remaining = (DELAY_MS - elapsed) / 1000;


    // Send countdown updates to phone every second

    static unsigned long lastTickMs = 0;

    if (millis() - lastTickMs >= 1000) {

      lastTickMs = millis();

      if (elapsed < DELAY_MS) {

        sendToPhone("Time remaining: " + String(remaining) + "s");

        Serial.println("Countdown: " + String(remaining) + "s remaining");

      }

    }


    // Countdown finished — activate alarm

    if (elapsed >= DELAY_MS) {

      Serial.println(">>> Countdown done! Sending ALARM_START to Arduino.");

      sendToPhone("Alarm is now ACTIVE.");

      ArduinoSerial.println("ALARM_START");

      isCountingDown = false;

    }

  }


  // Listen for FSR data from Arduino

  if (ArduinoSerial.available()) {

    String msg = ArduinoSerial.readStringUntil('\n');

    msg.trim();


    if (msg.startsWith("FSR:")) {

      String data = msg.substring(4);

      int vals[4];

      int idx = 0;


      while (idx < 4) {

        int comma = data.indexOf(',');

        if (comma == -1) {

          vals[idx] = data.toInt();

          break;

        }

        vals[idx] = data.substring(0, comma).toInt();

        data = data.substring(comma + 1);

        idx++;

      }


      // Print to ESP32 serial monitor

      Serial.print("FSR Readings -> ");

      for (int i = 0; i < 4; i++) {

        Serial.print(vals[i]); Serial.print(" ");

      }

      Serial.println();


      // Forward to phone app

      String btOut = "FSR0:" + String(vals[0]) + " FSR1:" + String(vals[1]) +

                     " FSR2:" + String(vals[2]) + " FSR3:" + String(vals[3]);

      sendToPhone(btOut);

    }

  }

}
