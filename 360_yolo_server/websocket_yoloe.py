import asyncio
import websockets
import base64
import json
from datetime import datetime
import cv2
import numpy as np
from ultralytics import YOLOE
import io
from PIL import Image

HOST = '0.0.0.0'
PORT = 8765

 
# YOLO-E provides better efficiency and accuracy balance
model = YOLOE('yoloe-v8s-seg-pf.pt')  # YOLOv8 Efficient model
# Print the model's class names
print("Model can detect:", model.names)

def process_image_with_yolo(img_bytes, confidence_threshold=0.2):
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
                    # Get bounding box coordinates
                    x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                    
                    # Get confidence and class
                    confidence = float(box.conf[0].cpu().numpy())
                    class_id = int(box.cls[0].cpu().numpy())
                    class_name = model.names[class_id]
                    
                    # Calculate center point and dimensions
                    center_x = int((x1 + x2) / 2)
                    center_y = int((y1 + y2) / 2)
                    width = int(x2 - x1)
                    height = int(y2 - y1)
                    
                    detected_objects.append({
                        'class_name': class_name,
                        'confidence': round(confidence, 3),
                        'bbox': {
                            'x1': int(x1),
                            'y1': int(y1),
                            'x2': int(x2),
                            'y2': int(y2),
                            'center_x': center_x,
                            'center_y': center_y,
                            'width': width,
                            'height': height
                        }
                    })
        
        return detected_objects
        
    except Exception as e:
        print(f"[ERROR] YOLO processing failed: {e}")
        return None

async def handle_client(websocket):
    print(f"[INFO] Client connected: {websocket.remote_address}")
    # Buffer for images/results per client
    angle_buffer = {}
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                if data.get('type') == 'image':
                    angle = data.get('angle')
                    img_b64 = data.get('data')
                    confidence_threshold = data.get('confidence', 0.5)  # Default confidence threshold
                    
                    # Validate required fields
                    if angle is None or img_b64 is None:
                        await websocket.send(json.dumps({
                            'status': 'error', 
                            'error': 'Missing angle or data'
                        }))
                        continue
                    
                    # Decode image
                    try:
                        img_bytes = base64.b64decode(img_b64)
                    except base64.binascii.Error:
                        await websocket.send(json.dumps({
                            'status': 'error', 
                            'error': 'Invalid base64 data'
                        }))
                        continue
                    
                    # Save original image (optional, for debugging)
                    now = datetime.now().strftime('%Y%m%d_%H%M%S_%f')
                    filename = f"received_{angle}_{now}.png"
                    
                    with open(filename, 'wb') as f:
                        f.write(img_bytes)
                    
                    print(f"[RECV] Image received at angle {angle}, saved as {filename}")
                    
                    # Process image with YOLO
                    print(f"[PROC] Running YOLO detection on image at angle {angle}...")
                    detected_objects = process_image_with_yolo(img_bytes, confidence_threshold)
                    
                    # Buffer the result
                    angle_buffer[int(angle)] = {
                        'angle': angle,
                        'filename': filename,
                        'detection_results': {
                            'objects_count': len(detected_objects) if detected_objects else 0,
                            'objects': detected_objects if detected_objects else [],
                            'confidence_threshold': confidence_threshold
                        }
                    }
                    
                    print(f"[DETECT] Found {len(detected_objects) if detected_objects else 0} objects at angle {angle}")
                    if detected_objects:
                        for obj in detected_objects:
                            print(f"  - {obj['class_name']}: {obj['confidence']}")
                    
                    # If all four angles are received, send the combined response
                    required_angles = {0, 90, 180, 270}
                    if required_angles.issubset(angle_buffer.keys()):
                        # Sort by angle for consistency
                        all_results = [angle_buffer[a] for a in sorted(required_angles)]
                        response = {
                            'status': 'success',
                            'all_angles': all_results
                        }
                        await websocket.send(json.dumps(response))
                        angle_buffer.clear()  # Reset for next round
                
                elif data.get('type') == 'ping':
                    # Health check endpoint
                    await websocket.send(json.dumps({
                        'status': 'success',
                        'message': 'Server is running',
                        'model_loaded': True
                    }))
                
                else:
                    print(f"[WARN] Unknown message type: {data.get('type')}")
                    await websocket.send(json.dumps({
                        'status': 'error', 
                        'error': 'Unknown message type'
                    }))
            
            except json.JSONDecodeError:
                await websocket.send(json.dumps({
                    'status': 'error', 
                    'error': 'Invalid JSON'
                }))
            
            except Exception as e:
                print(f"[ERROR] Unexpected error: {e}")
                await websocket.send(json.dumps({
                    'status': 'error', 
                    'error': 'Server error'
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