# MAV

A Flutter project for mobile assisted vision.

## Getting Started

This project provides a mobile application to assist visually impaired users with navigation and surrounding awareness.

### Prerequisites

Before running the application, ensure you have the following installed:

*   [Flutter SDK](https://flutter.dev/docs/get-started/install)
*   [Python 3.6+](https://www.python.org/downloads/)
*   [pip](https://pip.pypa.io/en/stable/installing/) (Python package installer)

### Setup

1.  **Clone the repository:**

    ```bash
    git clone <repository_url>
    cd MAV
    ```

2.  **Install Flutter dependencies:**

    ```bash
    flutter pub get
    ```

3.  **Configure Environment Variables:**

    Create a file named `.env` in the `assets/` directory of the Flutter project. Add the following variables to the `.env` file:

    ```
    GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY
    IP_ADDRESS=YOUR_SERVER_IP_ADDRESS
    PORT=YOUR_SERVER_PORT
    ```

    *   `GOOGLE_MAPS_API_KEY`: Obtain an API key from the [Google Maps Platform](https://console.cloud.google.com/google/maps-apis/overview).
    *   `IP_ADDRESS`: The IP address of the machine running the Python server (e.g., `127.0.0.1` for localhost, or a local network IP like `192.168.1.100`).
    *   `PORT`: The port number on which the Python server is listening (default is `8765`).

    **Important:** Ensure that the `assets/` directory and the `.env` file are included in your `pubspec.yaml` file:

    ```yaml
    flutter:
      assets:
        - assets/.env
        # other assets...
    ```

    Also configure the `GOOGLE_MAPS_API_KEY` in the `local.properties` file:

    1.  Open the `local.properties` file located in the `android` directory of your Flutter project. If the file doesn't exist, create it.
    2.  Add the following line to the `local.properties` file, replacing `YOUR_GOOGLE_MAPS_API_KEY` with your actual API key:

        ```
        GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY
        ```

4.  **Run the Python Server:**

    Navigate to the `python_server` directory:

    ```bash
    cd python_server
    ```

    Install the required Python packages:

    ```bash
    pip install websockets Pillow opencv-python ultralytics numpy
    ```

    Run the Python server:

    ```bash
    python websocket_yoloe.py
    ```

    **Note:** The server will print the IP address and port it's listening on. Make sure these match the values in your `.env` file.

    *   To find your machine's IP address, use the following command:
        *   **Windows:** Open Command Prompt and type `ipconfig`. Look for the "IPv4 Address" under your network adapter (e.g., "Ethernet adapter Ethernet" or "Wireless LAN adapter Wi-Fi").
        *   **Linux/macOS:** Open a terminal and type `ifconfig`. Look for the "inet" address under your network interface (e.g., "eth0" or "wlan0").

    The server logs will also show the IP address it's binding to (e.g., `[INFO] Starting WebSocket server on ws://0.0.0.0:8765`). If it shows `0.0.0.0`, it means the server is listening on all available interfaces. You'll need to use your machine's actual IP address in the `.env` file for other devices on the network to connect.

5.  **Configure Server Address in Flutter:**

    The Flutter application reads the server IP address and port from the `.env` file. Ensure that the `IP_ADDRESS` and `PORT` values in the `.env` file match the actual IP address and port on which the Python server is running.

6.  **Run the Flutter Application:**

    Connect a physical Android or iOS device, or start an emulator. Then, run the Flutter application:

    ```bash
    flutter run
    ```

    The application should now connect to the Python server and be able to use the surrounding awareness features.

### Troubleshooting

*   **Server Connection Issues:**
    *   Verify that the Python server is running and accessible from your device or emulator.
    *   Double-check the `IP_ADDRESS` and `PORT` values in your `.env` file.
    *   Ensure that your device or emulator and the server are on the same network, or that appropriate network configurations (e.g., port forwarding) are set up.
*   **Google Maps API Key Issues:**
    *   Ensure that the `GOOGLE_MAPS_API_KEY` is valid and has the necessary permissions enabled in the Google Cloud Console.
    *   Check that the API key is correctly placed in the `.env` file.

### Additional Resources

*   [Flutter Documentation](https://docs.flutter.dev/)
*   [Google Maps Platform](https://console.cloud.google.com/google/maps-apis/overview)
*   [Ultralytics YOLOv8 Documentation](https://docs.ultralytics.com/)