# 🛡️ Tourist Safety & Emergency Location Tracking System

An integrated **IoT Hardware Wearable Device + Mobile Application** system designed to ensure the safety of tourists, enable real-time location monitoring for tour guides, and provide instant SOS emergency broadcasting.

---

## 📌 Features

- **📍 Dual Location Tracking**:
  - **Phone GPS Mode**: Uses the smartphone's internal GPS.
  - **IoT Wearable Mode**: Receives live GPS coordinates directly from the ESP8266 wearable device via Firebase Realtime Database.
- **🚨 Instant SOS Panic Alert**:
  - Emergency button on the IoT device triggers instant visual (OLED) and audible (Buzzer) feedback.
  - Broadcasts real-time emergency notifications to the Tour Guide dashboard with live GPS coordinates.
- **🗺️ Live Google Maps Navigation**:
  - Displays real-time positions of group members and tour guides.
  - Automatic boundary fitting and path updates.
- **🔗 Seamless Hardware Pairing**:
  - Link hardware devices (e.g. `DEV-01`) directly to user accounts without manual code edits.
- **💬 Real-Time Group Chat & Messaging**:
  - Built-in Firestore chat stream for communication between tourists and guides.

---

## System Architecture & Technology Stack

| Layer | Technologies Used |
| :--- | :--- |
| **Mobile Application** | Flutter, Dart, Google Maps SDK, Provider/State Management |
| **Backend & Cloud Services** | Firebase Authentication, Cloud Firestore, Firebase Realtime Database (RTDB) |
| **IoT Hardware Node** | ESP8266 NodeMCU, NEO-6M GPS Module, SSD1306 OLED Display (128x64 I2C), Active Buzzer, Push Button |
| **Firmware Language** | C++ (Arduino Framework, FirebaseESPClient, TinyGPS++) |

---

## Repository Project Structure

```text
tourist_safety_app/
├── android/                 # Native Android build configurations
├── ios/                     # iOS configuration files
├── lib/                     # Flutter Application Source Code
│   ├── main.dart            # App Entry point
│   ├── screens/             # UI Screens (Tourist & Guide Dashboards, Login, SOS, Chat)
│   ├── services/            # Firebase, Location, and Device Services
│   └── theme/               # Application Theme & Color Palette
├── hardware/                # IoT Firmware Code
│   └── esp8266_firmware/    # ESP8266 C++ Arduino Code (.ino)
├── pubspec.yaml             # Flutter Dependencies & Assets
└── README.md                # Project Documentation
```

---

## Getting Started

### 1. Prerequisites
- **Flutter SDK**: `^3.5.0` (or compatible version)
- **Android Studio / VS Code** with Flutter extensions.
- **Arduino IDE** (for flashing ESP8266 firmware).

### 2. Mobile App Setup
```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/tourist_safety_app.git

# Navigate into the project folder
cd tourist_safety_app/tourist_safety_app

# Install dependencies
flutter pub get

# Run on emulator/device
flutter run
```

### 3. Hardware Firmware Setup
1. Open `hardware/esp8266_firmware/esp8266_firmware.ino` in **Arduino IDE**.
2. Install required libraries via Library Manager:
   - `Firebase ESP Client`
   - `Adafruit SSD1306` & `Adafruit GFX`
   - `TinyGPSPlus`
3. Select board **NodeMCU 1.0 (ESP-12E Module)**.
4. Verify WiFi SSID & Password and upload to ESP8266.

---

## Security & Privacy
- Location updates are strictly scoped within active tourist group codes.
- Realtime Database security rules ensure authenticated user access.
