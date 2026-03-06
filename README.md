# InvisiGuard - Final Year Project

InvisiGuard is a comprehensive health and safety monitoring system designed to provide real-time alerts and location tracking for vulnerable individuals. The system consists of a Flutter-based mobile application (`invisiguard_app`) and a machine learning module (`invisiguardmodel`) for advanced motion and fall detection.

## Key Features

- **Fall Detection:** Real-time ML-powered detection of falls with minimizing false positives. Employs refined logic to differentiate between normal motion and sudden falls.
- **Motion Detection:** Tracks general motion and activity levels.
- **SOS Alerts:** Quick-access SOS functionality to instantly trigger emergency alerts.
- **Geofence Alerts:** Set up safe zones and receive notifications if the user exits the designated boundaries.
- **Map & Location History:** view real-time minimap and keep a history of locations saved periodically (e.g., every 3 minutes).
- **Architecture:** Communicates via a robust backend, with Firebase integrations for authentication, database, and system-level cloud messaging (FCM).

## Project Structure

- `final-year-project-invisiguard/invisiguard_app/`: The frontend Flutter mobile application.
- `final-year-project-invisiguard/invisiguardmodel/`: The backend machine learning models (Python), including scripts such as `detect_motion_ml.py`.

## Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/)
- [Python 3.x](https://www.python.org/)
- Firebase account for app configuration (Note: ensure `serviceAccountKey.json` is configured securely, do not commit to version control).

### Running the App
1. Navigate to the `invisiguard_app` directory:
   ```bash
   cd final-year-project-invisiguard/invisiguard_app
   ```
2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```

### Running the ML Model
1. Navigate to the `invisiguardmodel` directory:
   ```bash
   cd final-year-project-invisiguard/invisiguardmodel
   ```
2. Install Python dependencies (e.g., using `pip`).
3. Execute the motion detection training or inference scripts:
   ```bash
   python detect_motion_ml.py
   ```

## Documentation
- `Invisiguard_Architecture_Block_Diagram.docx`: Contains the high-level system architecture.
- `Invisiguard_Frontend_Backend_Connectivity.docx`: Details the integration and communication flow between the mobile app frontend and ML/server backend.
![WhatsApp Image 2026-02-28 at 9 16 16 PM](https://github.com/user-attachments/assets/5d0722bf-2abe-4a94-9eb6-e3e78fccd987)
![WhatsApp Image 2026-02-28 at 9 16 16 PM (2)](https://github.com/user-attachments/assets/252fb7bb-2bec-4725-b6cd-8e5d9bd8e78e)
![WhatsApp Image 2026-02-28 at 9 16 16 PM (1)](https://github.com/user-attachments/assets/b5aed4ef-0871-44dd-b53c-d4b3ed153cd2)
![WhatsApp Image 2026-02-28 at 9 16 15 PM](https://github.com/user-attachments/assets/7e025e00-0f66-4c50-a08f-330b53ce75bd)
![WhatsApp Image 2026-02-28 at 9 16 15 PM (1)](https://github.com/user-attachments/assets/0259f7f6-6340-4195-96ec-5c4e49e5a5d8)
![WhatsApp Image 2026-02-28 at 9 16 14 PM](https://github.com/user-attachments/assets/3167fe83-f641-490d-97ed-590727cab0c6)
![WhatsApp Image 2026-02-28 at 9 16 14 PM (1)](https://github.com/user-attachments/assets/197ba407-88bd-4faf-8df8-14a17abc56de)
![WhatsApp Image 2026-02-28 at 9 16 13 PM](https://github.com/user-attachments/assets/3991748e-8cea-4100-b069-a71bac34a59c)
![WhatsApp Image 2026-02-28 at 9 16 13 PM (2)](https://github.com/user-attachments/assets/c4e973c9-e75b-4504-9392-6eacca8f0d02)
![WhatsApp Image 2026-02-28 at 9 16 13 PM (1)](https://github.com/user-attachments/assets/40b69d44-3872-4ea4-bf40-4628ca180ec1)
![WhatsApp Image 2026-02-28 at 9 16 12 PM](https://github.com/user-attachments/assets/6bb143c8-8e92-4cb4-baf5-5035b10aed43)
![WhatsApp Image 2026-02-28 at 9 16 12 PM (1)](https://github.com/user-attachments/assets/1e06ac81-b4b5-4a5b-95ba-d38066151c44)
