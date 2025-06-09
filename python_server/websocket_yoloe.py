import asyncio
import base64
import cv2
import io
import json
import numpy as np
import os
import time
import uuid
import websockets
from datetime import datetime
from ultralytics import YOLOE
from PIL import Image

HOST = '0.0.0.0'
PORT = 8765

# YOLO-E provides better efficiency and accuracy balance
model = YOLOE('yoloe-v8s-seg-pf.pt')  # YOLOv8 Efficient model
# Print the model's class names
print("Model can detect:", model.names)


def process_image_with_yolo(img_bytes, confidence_threshold=0.9):
    """
    Process image with YOLO and return detected objects
    """
    try:
        # Convert bytes to PIL Image
        image = Image.open(io.BytesIO(img_bytes))

        # Convert PIL to OpenCV format
        opencv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)

        # Run YOLO inference
        results = model(opencv_image, conf=confidence_threshold)

        detected_objects = []

        # Process results
        for result in results:
            boxes = result.boxes
            if boxes is not None:
                for box in boxes:
                    class_id = int(box.cls.item())
                    class_name = model.names[class_id]
                    confidence = float(box.conf.item())
                    x1, y1, x2, y2 = [int(coord)
                                      for coord in box.xyxy[0].tolist()]

                    detected_objects.append({
                        'class_id': class_id,
                        'class_name': class_name,
                        'confidence': confidence,
                        'bbox': [x1, y1, x2, y2]
                    })

        return detected_objects

    except Exception as e:
        print(f"[ERROR] YOLO processing failed: {e}")
        return None


async def handle_client(websocket):
    print(f"[INFO] Client connected: {websocket.remote_address}")
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                if data.get('type') == 'image':
                    # Extract image data and confidence threshold
                    img_b64 = data.get('data')
                    confidence_threshold = data.get('confidence', 0.3)

                    # Generate a unique filename
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    unique_id = str(uuid.uuid4())[:8]
                    filename = f"detection_{timestamp}_{unique_id}.jpg"

                    # Process the base64 image
                    if img_b64:
                        img_bytes = base64.b64decode(img_b64)
                        start_time = time.time()
                        detected_objects = process_image_with_yolo(
                            img_bytes, confidence_threshold)
                        process_time = time.time() - start_time

                        # Count objects by class
                        class_counts = {}
                        if detected_objects:
                            for obj in detected_objects:
                                class_name = obj['class_name']
                                class_counts[class_name] = class_counts.get(
                                    class_name, 0) + 1

                        response = {
                            'status': 'success',
                            'detection_results': {
                                'objects_count': sum(class_counts.values()),
                                'class_counts': class_counts,
                                'confidence_threshold': confidence_threshold,
                                'process_time_ms': int(process_time * 1000)
                            }
                        }
                        await websocket.send(json.dumps(response))
                        print(
                            f"[INFO] Processed image '{filename}' with {sum(class_counts.values())} objects detected: {class_counts}")
                    else:
                        await websocket.send(json.dumps({
                            'status': 'error',
                            'error': 'No image data provided'
                        }))

                elif data.get('type') == 'ping':
                    # Respond to ping requests for connection testing
                    await websocket.send(json.dumps({
                        'status': 'success',
                        'message': 'Server is running'
                    }))
                    print(
                        f"[INFO] Ping received from {websocket.remote_address}")

                else:
                    # Handle unknown request types
                    await websocket.send(json.dumps({
                        'status': 'error',
                        'error': 'Unknown request type'
                    }))

            except json.JSONDecodeError:
                await websocket.send(json.dumps({
                    'status': 'error',
                    'error': 'Invalid JSON format'
                }))

            except Exception as e:
                print(f"[ERROR] Request processing error: {e}")
                await websocket.send(json.dumps({
                    'status': 'error',
                    'error': str(e)
                }))

    except websockets.ConnectionClosed:
        print(f"[INFO] Client disconnected: {websocket.remote_address}")

    except Exception as e:
        print(f"[ERROR] Connection error: {e}")


async def main():
    print(f"[INFO] Loading YOLOv8-E model (trained on 4.5k datasets)...")
    print(f"[INFO] Model loaded successfully: {model.model}")
    print(f"[INFO] Model classes available: {len(model.names)}")
    print(f"[INFO] Starting WebSocket server on ws://{HOST}:{PORT}")

    async with websockets.serve(handle_client, HOST, PORT, max_size=10*1024*1024):
        print(f"[INFO] WebSocket server is running and listening for connections...")
        print(f"[INFO] Ready to receive images and perform object detection!")
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
