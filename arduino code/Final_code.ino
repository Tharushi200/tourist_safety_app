#include <ESP8266WiFi.h>
#include <Firebase_ESP_Client.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <TinyGPS++.h>
#include <SoftwareSerial.h>

#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// HARDWARE & NETWORK CONFIGURATION

#define NETWORK_SSID       "Pixel_7500"
#define NETWORK_PASS       "Tharushi"

#define FIREBASE_AUTH_KEY  "AIzaSyBQpA6jvJAdobhqUyzNO9fuDMJkijZ2ceg"
#define FIREBASE_DB_URL    "hhttps://tourist-safety-app-aa6b3-default-rtdb.firebaseio.com/"

#define HARDWARE_NODE_ID   "DEV-01"  // Permanent Hardware Serial ID

// Pin Definitions
#define PIN_EMERGENCY_BTN  D6        // SOS Push Button
#define PIN_AUDIO_ALARM    D5        // Active/Passive Buzzer
#define PIN_OLED_SDA       D2
#define PIN_OLED_SCL       D1
#define PIN_GPS_RX         D7
#define PIN_GPS_TX         D8

// OLED Display Parameters
#define DISPLAY_WIDTH      128
#define DISPLAY_HEIGHT     64
#define RESET_OLED_PIN     -1

// DATA STRUCTURES & STATE ENUMS

enum DeviceMode {
  MODE_UNLINKED,      // Waiting for app to pair
  MODE_LINKED_IDLE,  // Paired but no active group
  MODE_TRACKING,     // Active group, pushing location
  MODE_EMERGENCY     // SOS Active
};

struct TouristSession {
  String uid;
  String displayName;
  String groupCode;
  bool isPaired;
};

struct LocationMetrics {
  double lat;
  double lng;
  bool validSignal;
  uint8_t satellites;
};

// Global Instance Declarations
Adafruit_SSD1306 oledDisplay(DISPLAY_WIDTH, DISPLAY_HEIGHT, &Wire, RESET_OLED_PIN);
TinyGPSPlus gpsModule;
SoftwareSerial gpsPort(PIN_GPS_RX, PIN_GPS_TX);

FirebaseData fbDataObj;
FirebaseAuth fbAuthObj;
FirebaseConfig fbConfigObj;

TouristSession activeSession = {"", "", "", false};
LocationMetrics currentGeo = {6.9271, 79.8612, false, 0}; // Default Sri Lanka fallbacks
DeviceMode currentMode = MODE_UNLINKED;

bool firebaseConnected = false;

// Timers for Non-blocking Execution
unsigned long prevTelemetryMs = 0;
const unsigned long TELEMETRY_INTERVAL = 4000; // Push location every 4s

unsigned long prevRegistrationPollMs = 0;
const unsigned long REGISTRATION_POLL_INTERVAL = 5000; // Check pairing status every 5s

// Function Declarations
void initializeHardware();
void connectWiFiNetwork();
void setupFirebaseClient();
void fetchNodeRegistration();
void pushLocationTelemetry();
void dispatchPanicBroadcast();
void renderOledInterface();
void triggerAlarmBeep(uint16_t freq, uint16_t durationMs);

// SETUP
void setup() {
  Serial.begin(115200);
  delay(200);

  Serial.println(F("\n======================================"));
  Serial.println(F(" TOURIST SAFETY SYSTEM - IOT NODE     "));
  Serial.print(F(" NODE IDENTIFIER: "));
  Serial.println(F(HARDWARE_NODE_ID));
  Serial.println(F("======================================\n"));

  initializeHardware();
  connectWiFiNetwork();
  setupFirebaseClient();

  // Initial Sync Check
  fetchNodeRegistration();
}

// MAIN LOOP

void loop() {
  // 1. Maintain WiFi Connection
  if (WiFi.status() != WL_CONNECTED) {
    WiFi.reconnect();
    delay(500);
    return;
  }

  // 2. Decode GPS Serial Stream
  while (gpsPort.available() > 0) {
    gpsModule.encode(gpsPort.read());
  }

  if (gpsModule.location.isUpdated()) {
    currentGeo.lat = gpsModule.location.lat();
    currentGeo.lng = gpsModule.location.lng();
    currentGeo.validSignal = gpsModule.location.isValid();
    currentGeo.satellites = gpsModule.satellites.value();
  }

  // 3. Refresh Screen Interface
  renderOledInterface();

  const unsigned long currentMs = millis();

  // 4. Periodically Sync App Pairing Status (Every 5 seconds)
  if (Firebase.ready() && firebaseConnected && (currentMs - prevRegistrationPollMs >= REGISTRATION_POLL_INTERVAL)) {
    prevRegistrationPollMs = currentMs;
    fetchNodeRegistration();
  }

  // 5. Transmit Telemetry if Linked & Group Joined (Every 4 seconds)
  if (Firebase.ready() && firebaseConnected && activeSession.isPaired && activeSession.groupCode.length() > 0) {
    if (currentMs - prevTelemetryMs >= TELEMETRY_INTERVAL) {
      prevTelemetryMs = currentMs;
      pushLocationTelemetry();
    }
  }

  // 6. Emergency Button Detection
  if (digitalRead(PIN_EMERGENCY_BTN) == LOW) {
    dispatchPanicBroadcast();
    while (digitalRead(PIN_EMERGENCY_BTN) == LOW) {
      ESP.wdtFeed();
      delay(30);
    }
    delay(200);
  }

  delay(20);
}

// HARDWARE INITIALIZATION

void initializeHardware() {
  pinMode(PIN_EMERGENCY_BTN, INPUT_PULLUP);
  pinMode(PIN_AUDIO_ALARM, OUTPUT);
  digitalWrite(PIN_AUDIO_ALARM, LOW);

  gpsPort.begin(9600);
  Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);

  if (oledDisplay.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    oledDisplay.clearDisplay();
    oledDisplay.setTextColor(WHITE);
    oledDisplay.setTextSize(1);
    oledDisplay.drawRoundRect(4, 4, 120, 56, 8, WHITE);
    oledDisplay.setCursor(14, 20);
    oledDisplay.println(F("TOURIST SAFETY"));
    oledDisplay.setCursor(24, 38);
    oledDisplay.println(F("NODE BOOTING..."));
    oledDisplay.display();
    delay(1200);
  }
}

// WIFI CONNECTION & TIME SYNC

void connectWiFiNetwork() {
  oledDisplay.clearDisplay();
  oledDisplay.setCursor(10, 25);
  oledDisplay.println(F("Connecting WiFi..."));
  oledDisplay.display();

  WiFi.begin(NETWORK_SSID, NETWORK_PASS);
  uint8_t retries = 0;
  while (WiFi.status() != WL_CONNECTED && retries < 25) {
    delay(500);
    Serial.print(F("."));
    retries++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println(F("\n[WiFi] Connected successfully!"));
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
    time_t now = time(nullptr);
    uint8_t timeout = 0;
    while (now < 8 * 3600 * 2 && timeout < 12) {
      delay(300);
      now = time(nullptr);
      timeout++;
    }
  } else {
    Serial.println(F("\n[WiFi] Connection Failed. Proceeding..."));
  }
}

// FIREBASE INITIALIZATION

void setupFirebaseClient() {
  fbConfigObj.api_key = FIREBASE_AUTH_KEY;
  fbConfigObj.database_url = FIREBASE_DB_URL;
  fbConfigObj.token_status_callback = tokenStatusCallback;
  fbConfigObj.timeout.serverResponse = 12000;
  
  fbDataObj.setBSSLBufferSize(4096, 1024);
  fbDataObj.setResponseSize(2048);

  Firebase.begin(&fbConfigObj, &fbAuthObj);
  Firebase.reconnectWiFi(true);

  if (Firebase.signUp(&fbConfigObj, &fbAuthObj, "", "")) {
    firebaseConnected = true;
    Serial.println(F("[Firebase] Authentication Initialized"));
  } else {
    Serial.print(F("[Firebase] Auth Warning: "));
    Serial.println(fbConfigObj.signer.signupError.message.c_str());
  }

  unsigned long startWait = millis();
  while (!Firebase.ready() && (millis() - startWait < 10000)) {
    ESP.wdtFeed();
    delay(200);
  }

  if (Firebase.ready()) {
    Serial.println(F("[Firebase] Connection Ready!"));
    firebaseConnected = true;
  }
}

// NODE REGISTRATION POLL (/devices/DEV-01)

void fetchNodeRegistration() {
  if (!Firebase.ready() || !firebaseConnected) return;

  String devicePath = "/devices/" + String(HARDWARE_NODE_ID);
  ESP.wdtFeed();

  if (Firebase.RTDB.getJSON(&fbDataObj, devicePath)) {
    FirebaseJson &json = fbDataObj.jsonObject();
    FirebaseJsonData fieldData;

    json.get(fieldData, "userId");
    String fetchedUid = fieldData.success ? fieldData.stringValue : "";

    if (fetchedUid.length() > 3 && fetchedUid != "null") {
      activeSession.uid = fetchedUid;
      activeSession.isPaired = true;

      json.get(fieldData, "userName");
      activeSession.displayName = fieldData.success ? fieldData.stringValue : "Tourist";

      json.get(fieldData, "groupId");
      if (fieldData.success && fieldData.stringValue.length() > 0 && fieldData.stringValue != "null") {
        activeSession.groupCode = fieldData.stringValue;
        currentMode = MODE_TRACKING;
      } else {
        activeSession.groupCode = "";
        currentMode = MODE_LINKED_IDLE;
      }

      Serial.print(F("[NODE LINKED] User: "));
      Serial.print(activeSession.displayName);
      Serial.print(F(" | Group: "));
      Serial.println(activeSession.groupCode);
    } else {
      activeSession.isPaired = false;
      activeSession.uid = "";
      activeSession.displayName = "";
      activeSession.groupCode = "";
      currentMode = MODE_UNLINKED;
      Serial.println(F("[NODE UNLINKED] Device currently available"));
    }
  } else {
    Serial.print(F("[NODE SYNC FAIL] "));
    Serial.println(fbDataObj.errorReason());
    activeSession.isPaired = false;
    currentMode = MODE_UNLINKED;
  }
  ESP.wdtFeed();
}

// PUSH TELEMETRY TO FIREBASE (/groups/{groupId}/locations/{userId})

void pushLocationTelemetry() {
  if (!activeSession.isPaired || activeSession.groupCode.length() == 0 || activeSession.uid.length() == 0) return;

  String targetPath = "/groups/" + activeSession.groupCode + "/locations/" + activeSession.uid;

  FirebaseJson payload;
  payload.set("userId", activeSession.uid);
  payload.set("name", activeSession.displayName);
  payload.set("lat", currentGeo.lat);
  payload.set("lng", currentGeo.lng);
  payload.set("role", "tourist");
  payload.set("isSOS", false);
  payload.set("battery", 95);
  payload.set("timestamp", (int)(millis() / 1000));

  if (Firebase.RTDB.setJSON(&fbDataObj, targetPath, &payload)) {
    Serial.println(F("[TELEMETRY] Coordinates pushed successfully"));
  } else {
    Serial.print(F("[TELEMETRY FAIL] "));
    Serial.println(fbDataObj.errorReason());
  }
}

// DISPATCH EMERGENCY SOS ALERT

void dispatchPanicBroadcast() {
  Serial.println(F("\n🚨 [EMERGENCY] SOS BUTTON TRIGGERED!"));

  // Visual SOS Alert
  oledDisplay.clearDisplay();
  oledDisplay.drawRect(0, 0, 128, 64, WHITE);
  oledDisplay.drawRect(2, 2, 124, 60, WHITE);
  oledDisplay.setTextSize(3);
  oledDisplay.setCursor(36, 20);
  oledDisplay.println(F("SOS"));
  oledDisplay.display();

  // Audio Siren Tone Pattern
  for (uint8_t i = 0; i < 3; i++) {
    triggerAlarmBeep(1800, 180);
    delay(80);
    triggerAlarmBeep(2400, 220);
    delay(80);
  }

  if (Firebase.ready() && firebaseConnected && activeSession.isPaired && activeSession.groupCode.length() > 0) {
    String alertKey = "sos_" + String(millis());
    String alertPath = "/groups/" + activeSession.groupCode + "/alerts/" + alertKey;

    FirebaseJson alertBody;
    alertBody.set("id", alertKey);
    alertBody.set("userId", activeSession.uid);
    alertBody.set("userName", activeSession.displayName);
    alertBody.set("type", "sos");
    alertBody.set("message", activeSession.displayName + " emitted an emergency SOS!");
    alertBody.set("lat", currentGeo.lat);
    alertBody.set("lng", currentGeo.lng);
    alertBody.set("acknowledged", false);
    alertBody.set("timestamp", (int)(millis() / 1000));

    // 1. Push Alert JSON Object
    Firebase.RTDB.setJSON(&fbDataObj, alertPath, &alertBody);

    // 2. Mark member status isSOS = true
    String flagPath = "/groups/" + activeSession.groupCode + "/locations/" + activeSession.uid + "/isSOS";
    Firebase.RTDB.setBool(&fbDataObj, flagPath, true);

    Serial.println(F("[EMERGENCY] SOS Broadcast successfully transmitted to Firebase"));
  }
}

// Helper Alarm Tone Generator
void triggerAlarmBeep(uint16_t freq, uint16_t durationMs) {
  tone(PIN_AUDIO_ALARM, freq, durationMs);
  delay(durationMs);
  noTone(PIN_AUDIO_ALARM);
}

// OLED UI RENDERING ENGINE

void renderOledInterface() {
  oledDisplay.clearDisplay();
  oledDisplay.setTextSize(1);
  oledDisplay.setTextColor(WHITE);

  // Top Title Bar
  oledDisplay.setCursor(2, 2);
  oledDisplay.print(F("SMART TOURIST NODE"));
  oledDisplay.drawFastHLine(0, 12, 128, WHITE);

  if (!activeSession.isPaired) {
    // Unlinked State Layout
    oledDisplay.setCursor(4, 18);
    oledDisplay.print(F("ID   : ")); oledDisplay.println(F(HARDWARE_NODE_ID));
    oledDisplay.setCursor(4, 30);
    oledDisplay.println(F("MODE : UNPAIRED"));
    oledDisplay.drawRoundRect(2, 44, 124, 18, 4, WHITE);
    oledDisplay.setCursor(12, 49);
    oledDisplay.println(F("PAIR DEVICE VIA APP"));
  } else {
    // Linked State Layout
    oledDisplay.setCursor(4, 16);
    oledDisplay.print(F("USER : ")); oledDisplay.println(activeSession.displayName);

    oledDisplay.setCursor(4, 28);
    if (activeSession.groupCode.length() > 0) {
      oledDisplay.print(F("GROUP: ")); oledDisplay.println(activeSession.groupCode);
    } else {
      oledDisplay.println(F("GROUP: (WAITING)"));
    }

    oledDisplay.setCursor(4, 40);
    oledDisplay.print(F("LAT:")); oledDisplay.print(currentGeo.lat, 4);
    oledDisplay.print(F(" L:")); oledDisplay.println(currentGeo.lng, 4);

    oledDisplay.setCursor(4, 52);
    if (currentGeo.validSignal) {
      oledDisplay.print(F("GPS: FIX (SAT: "));
      oledDisplay.print(currentGeo.satellites);
      oledDisplay.println(F(")"));
    } else {
      oledDisplay.println(F("GPS: LOCATING..."));
    }
  }

  oledDisplay.display();
}
