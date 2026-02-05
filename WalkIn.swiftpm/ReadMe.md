# WalkIn 🚶‍♂️📍

**WalkIn** is an App Playground developed for the **2026 Swift Student Challenge**. It provides infrastructure-free indoor navigation using on-device sensor fusion and machine learning.

## 🚀 The Problem
Indoor navigation often fails because GPS cannot penetrate thick walls, and many buildings lack the budget for expensive Bluetooth beacon setups. WalkIn solves this by turning every user into a "pathfinder."

## 🛠️ Technical Implementation
- **Core Motion:** Tracks PDR (Pedestrian Dead Reckoning) using `CMPedometer` and `CMDeviceMotion`.
- **Altimeter:** Uses barometric pressure to detect floor changes.
- **Vision & Core ML:** Identifies landmarks to recalibrate positioning and eliminate sensor drift.
- **Privacy:** 100% on-device processing; no images or location data ever leave the device.
- **Lightweight Storage:** Navigation paths are stored as JSON nodes, keeping the project under the 25MB submission limit.

## 📱 Features
- **Path Recording:** Record a trail by simply walking and dropping "breadcrumbs."
- **AI Landmarks:** Use the camera to confirm your location via common objects (Stairs, Signs).
- **Offline First:** Designed to work in basements, elevators, and areas with zero connectivity.

## 🏗️ Requirements
- **Xcode 26.0+**
- **iOS 19.0+**
- **Hardware:** iPhone with Accelerometer, Gyroscope, and Barometer (Required for full testing).
