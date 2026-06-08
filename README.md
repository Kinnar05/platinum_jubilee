# Platinum_jubilee
Project from Platinium_jubilee competition.
# SmartSense EMS — Intelligent Energy Monitoring System for Campus Hostels

> **PIR + IR Sensor Fusion → Stateflow FSM → Appliance Control → Energy Dashboard**  
> Simulated in MATLAB/Simulink R2024 | Embedded prototype on ESP32

---

## Overview

SmartSense is a smart energy monitoring and automated control system designed to reduce electricity wastage in campus hostels. Thousands of students share electrical loads across hundreds of rooms and common areas, yet facility managers have little visibility into where and when wastage occurs. SmartSense addresses this by combining real-time occupancy sensing, finite-state-machine-based logic, and closed-loop relay control to automatically manage appliance loads — eliminating energy waste without requiring manual intervention.

The project has two parallel tracks:
- **Simulink Model** — A full system simulation in MATLAB R2024 validating the FSM logic, sensor fusion, energy accounting, and savings estimation.
- **ESP32 Hardware Prototype** — A physical proof-of-concept using PIR, DHT22, LEDs, and an I²C LCD display.
- https://wokwi.com/projects/466239196977045505

---

## Problem Statement

Campus hostels routinely waste electricity because:
- Lights and fans are left on in unoccupied rooms.
- Facility managers lack real-time visibility into room-level consumption.
- Corrective actions are reactive, not preventive.
- Small inefficiencies repeated across hundreds of rooms compound into significant financial and environmental losses.

SmartSense moves beyond traditional energy metering toward **intelligent, automated, and scalable** energy management.

---

## Key Features

- **Dual-sensor occupancy detection** — PIR (motion) and IR (proximity) signals are fused to reduce false positives and improve reliability.
- **Finite State Machine (FSM)** — A four-state Stateflow FSM governs room occupancy logic: `EMPTY → ENTERING → OCCUPIED → VACANT_DELAY`. Appliances are only switched on when occupancy is confirmed, and are switched off after a configurable vacancy timeout.
- **Automated appliance control** — Relay-based control of Light (40 W), Fan (70 W), and AC (1200 W) loads; conventional baseline load is 1310 W always-on.
- **Real-time energy accounting** — Separate tracking of smart-managed energy (`E_Smart`) vs. conventional always-on energy (`E_Conv`), with computed savings (`E_Savings`).
- **Energy Dashboard** — Scope displays and numeric indicators show power and cumulative energy in real time during simulation.
- **ESP32 hardware prototype** — Physical demonstration with PIR sensor, DHT22 (temperature/humidity), push button, RGB LEDs, and a 16×2 I²C LCD.

---

## System Architecture

```
┌─────────────────────┐     PIR_Out      ┌──────────────────┐
│  OccupancySignalGen │ ───────────────► │                  │  ctrl_state
│  (PIR + IR sensor   │     IR_Out       │  OccupancyFSM    │ ──────────────►┐
│   signal generator) │ ───────────────► │  (Stateflow FSM) │               │
└─────────────────────┘                  └──────────────────┘               │
                                                                             ▼
                                                               ┌─────────────────────┐
                                                               │  ApplianceController │
                                                               │  (Light/Fan/AC relay │
                                                               │   logic)             │
                                                               └──────────┬──────────┘
                                                                          │ P_Smart_Out
                                                                          │ P_Conv_Out
                                                                          ▼
                                                               ┌─────────────────────┐
                                                               │   EnergyCalculator   │
                                                               │  E_Smart / E_Conv /  │
                                                               │  E_Savings           │
                                                               └──────────┬──────────┘
                                                                          │
                                                                          ▼
                                                               ┌─────────────────────┐
                                                               │   Energy Dashboard   │
                                                               │  Scope_Energy        │
                                                               │  Display_Savings_Wh  │
                                                               └─────────────────────┘
```

### FSM States

| State | Code | Description |
|-------|------|-------------|
| `EMPTY` | 0 | No occupant detected; all smart loads OFF |
| `ENTERING` | 1 | Motion detected; transitioning to occupied |
| `OCCUPIED` | 2 | Room confirmed occupied; smart loads ON |
| `VACANT_DELAY` | 3 | Occupant left; loads remain ON for timeout period before switching OFF |

---

## Simulink Model

**File:** `SmartSense_EMS.slx`  
**Environment:** MATLAB R2024

### Subsystems

| Subsystem | Description |
|-----------|-------------|
| `OccupancySignalGen` | Generates synthetic PIR and IR sensor signals for simulation |
| `OccupancyFSM` | Stateflow chart implementing the four-state occupancy FSM |
| `ApplianceController` | Maps FSM state to appliance ON/OFF commands and computes instantaneous smart and conventional power |
| `EnergyCalculator` | Integrates power signals over time to compute cumulative energy (Wh) and savings |

### Logged Signals

- `out.log_PIR` — PIR sensor signal
- `out.log_IR` — IR sensor signal
- `out.log_State` — FSM state over time
- `out.log_P_Smart` — Smart-managed power profile
- `out.log_P_Conv` — Conventional (always-on) power profile

### Load Configuration

| Appliance | Power | Control |
|-----------|-------|---------|
| Light | 40 W | Smart (FSM-controlled) |
| Fan | 70 W | Smart (FSM-controlled) |
| AC | 1200 W | Smart (FSM-controlled) |
| Conventional baseline | 1310 W | Always ON |

---

## Hardware Prototype

**Microcontroller:** ESP32 DevKit  

### Components

| Component | Role |
|-----------|------|
| PIR Sensor | Motion-based occupancy detection |
| DHT22 | Ambient temperature and humidity monitoring |
| Push Button | Manual override / mode toggle |
| Blue LED | Occupied status indicator |
| Yellow LED | Vacancy delay / warning indicator |
| Red LED | Empty / all-off status indicator |
| 16×2 I²C LCD | Real-time display of occupancy state, temperature, and humidity |

### Wiring Summary

- PIR signal pin → ESP32 GPIO (digital input)
- DHT22 data pin → ESP32 GPIO (single-wire protocol)
- Push button → ESP32 GPIO with internal pull-up
- LEDs → ESP32 GPIO through current-limiting resistors
- LCD → ESP32 I²C bus (SDA/SCL)

---

## Getting Started

### Simulink Simulation

1. Open MATLAB R2024.
2. Load `SmartSense_EMS.slx`.
3. Run the simulation.
4. Observe `Scope_Energy`, `Scope_Power`, and `Scope_Sensors_FSM` for real-time plots.
5. Check `Display_Savings_Wh` for cumulative energy savings at the end of the simulation run.

### ESP32 Firmware

**Prerequisites**
- Arduino IDE or PlatformIO
- ESP32 board package
- Libraries: `DHT sensor library`, `LiquidCrystal_I2C`

**Steps**
```bash
# Clone the repository
git clone https://github.com/<your-username>/SmartSense-EMS.git
cd SmartSense-EMS/firmware

# Open SmartSense_ESP32.ino in Arduino IDE
# Select board: ESP32 Dev Module
# Select correct COM port
# Upload
```

---

## Repository Structure

```
SmartSense-EMS/
├── simulink/
│   ├── SmartSense_EMS.slx          # Main Simulink model
│   └── SmartSense_EMS_params.m     # Model parameters script
├── firmware/
│   └── SmartSense_ESP32/
│       └── SmartSense_ESP32.ino    # ESP32 Arduino sketch
├── docs/
│   ├── system_architecture.png
│   ├── simulink_screenshot.png
│   └── hardware_wiring.png
└── README.md
```

---

## Results

Simulation output shows a measured energy savings of approximately **1.151 × 10⁴ Wh** over the simulated occupancy cycle, demonstrating the effectiveness of FSM-controlled appliance management compared to a conventional always-on baseline.

---

## Future Work

- Deploy on a multi-room mesh network (ESP-NOW or MQTT over Wi-Fi).
- Integrate a cloud dashboard (e.g., ThingSpeak, Grafana) for facility-wide visibility.
- Add ML-based occupancy prediction to pre-emptively control loads.
- Extend to common areas (corridors, bathrooms, study halls).
- Mobile alert notifications for facility managers.

---

## License

This project is released under the [MIT License](LICENSE).

---

## Authors

SmartSense EMS — developed as part of a campus sustainability initiative.  
Simulated in MATLAB/Simulink R2024 | Prototype on ESP32.
