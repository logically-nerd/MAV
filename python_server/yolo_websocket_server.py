import asyncio
import base64
import functools
import cv2
import json
import logging
import numpy as np
import os
import torch
import websockets

from typing import Any, Dict, List, Optional, Union
from ultralytics import YOLO  # Fixed typo from YOLOE to YOLO
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("yolo_server.log")
    ]
)
logger = logging.getLogger('yolo_server')

class YoloModel:
    """Class for handling YOLO model operations."""
    
    def __init__(self, model_path: str, device: Union[int, str] = 0):
        """
        Initialize the YOLO model.
        
        Args:
            model_path: Path to the YOLO model weights
            device: Device to run inference on (0 for first GPU, 'cpu' for CPU)
        """
        self.model_path = model_path
        self.device = device
        self.model = None
        self.class_names = {}
        logger.info(f"Initializing YoloModel with model path: {model_path}")
        self.load_model()
    
    def load_model(self) -> None:
        """Load the YOLO model and extract class names."""
        try:
            logger.info(f"Loading YOLO model from {self.model_path}")
            
            # Check if model file exists
            if not os.path.exists(self.model_path):
                logger.error(f"Model file not found: {self.model_path}")
                model_dir = os.path.dirname(self.model_path) or "."
                logger.info(f"Available files in {model_dir}:")
                for file in os.listdir(model_dir):
                    if file.endswith(('.pt', '.pth', '.weights')):
                        logger.info(f"  - {file}")
                raise FileNotFoundError(f"Model file not found: {self.model_path}")
            
            # Verify the model file 
            file_size_mb = os.path.getsize(self.model_path) / (1024 * 1024)
            logger.info(f"Model file size: {file_size_mb:.2f} MB")
            
            # If the file is very small, it might be a config file, not the actual model
            if file_size_mb < 1.0:
                logger.warning(f"Model file is suspiciously small ({file_size_mb:.2f} MB). This may not be a valid model file.")
            
            # Force YOLO to use the absolute path
            abs_model_path = os.path.abspath(self.model_path)
            logger.info(f"Using absolute model path: {abs_model_path}")
            
            # Load the model using the absolute path
            from ultralytics.models.yolo import YOLO
            self.model = YOLO(abs_model_path)
            
            # Verify we're using the correct model file
            if hasattr(self.model, 'ckpt_path'):
                actual_path = self.model.ckpt_path
                logger.info(f"Actual model path being used: {actual_path}")
                if actual_path != abs_model_path and actual_path != self.model_path:
                    logger.warning(f"WARNING: Model is using {actual_path} instead of {abs_model_path}")
            
            # Print model information
            if hasattr(self.model, 'model') and hasattr(self.model.model, 'names'):
                logger.info(f"Model architecture: {type(self.model.model).__name__}")
            
            self.extract_class_names()
            
            if torch.cuda.is_available() and isinstance(self.device, int):
                logger.info(f"Using GPU: {torch.cuda.get_device_name(self.device)}")
            else:
                logger.info("Using CPU for inference")
        except Exception as e:
            logger.error(f"Error loading YOLO model: {e}")
            import traceback
            logger.error(traceback.format_exc())
            raise
    
    def extract_class_names(self) -> None:
        """Extract class names from the loaded YOLO model."""
        if hasattr(self.model, 'names'):
            self.class_names = self.model.names
            logger.info(f"Extracted {len(self.class_names)} class names: {list(self.class_names.values())}")
        else:
            logger.warning("Could not extract class names from model")
    
    def detect_objects(self, image: np.ndarray, conf: float = 0.25) -> Any:
        """
        Detect objects in an image using YOLO.
        
        Args:
            image: OpenCV image in numpy array format
            conf: Confidence threshold for detections
            
        Returns:
            Results from YOLO prediction
        """
        if self.model is None:
            raise ValueError("Model not loaded")
        
        # Log image information
        logger.info(f"Running detection on image with shape: {image.shape}")
        
        # Convert device to proper format
        device = str(self.device)
        if device.isdigit() and torch.cuda.is_available():
            device = f'cuda:{device}'
        else:
            device = 'cpu'
        
        results = self.model.predict(
            source=image,
            device=device,
            conf=conf,
            verbose=False
        )
        
        return results[0]  # Return the first result since we only process one image

    def process_results(self, results: Any) -> Dict[str, Any]:
        """
        Process YOLO results into a structured format.
        
        Args:
            results: Results from YOLO prediction
            
        Returns:
            Dictionary containing detections with bounding boxes, classes, and confidences
        """
        processed_data = {
            "timestamp": datetime.now().isoformat(),
            "detections": []
        }
        
        if hasattr(results, 'boxes') and len(results.boxes) > 0:
            boxes = results.boxes
            logger.info(f"Found {len(boxes)} detections")
            
            for i in range(len(boxes)):
                box = boxes[i]
                xyxy = box.xyxy[0].cpu().numpy()  # Move to CPU and convert to numpy
                x1, y1, x2, y2 = xyxy.tolist()  # Convert to list
                class_id = int(box.cls[0].item())
                confidence = float(box.conf[0].item())
                class_name = self.class_names.get(class_id, f"class_{class_id}")
                
                logger.info(f"Detection {i}: class={class_name}, confidence={confidence:.3f}, bbox=[{int(x1)}, {int(y1)}, {int(x2)}, {int(y2)}]")
                
                detection = {
                    "bbox": [int(x1), int(y1), int(x2), int(y2)],
                    "class_id": class_id,
                    "class_name": class_name,
                    "confidence": round(confidence, 3)
                }
                processed_data["detections"].append(detection)
        else:
            logger.info("No detections found in this frame")
        
        # Add segmentation data if available
        if hasattr(results, 'masks') and results.masks is not None:
            logger.info(f"Found {len(results.masks)} segmentation masks")
            for i, mask in enumerate(results.masks.data):
                if i < len(processed_data["detections"]):
                    binary_mask = (mask.cpu().numpy() > 0.5).astype(np.uint8) * 255
                    mask_rle = self.encode_binary_mask(binary_mask)
                    processed_data["detections"][i]["mask"] = mask_rle
        
        return processed_data
    
    @staticmethod
    def encode_binary_mask(mask: np.ndarray) -> Dict[str, Any]:
        """
        Encode binary mask using run-length encoding.
        
        Args:
            mask: Binary mask as numpy array
            
        Returns:
            Dictionary with shape and encoded values
        """
        # Flatten the mask and add padding
        mask = mask.flatten()
        pixels = np.concatenate([[0], mask, [0]])
        runs = np.where(pixels[1:] != pixels[:-1])[0] + 1
        runs[1::2] -= runs[::2]
        
        return {
            "size": mask.shape[0],
            "counts": runs.tolist()
        }

class YoloWebsocketServer:
    """WebSocket server for real-time YOLO object detection."""
    
    def __init__(self, model_path: str, host: str = "0.0.0.0", port: int = 8765, 
                 device: Union[int, str] = 0):
        """
        Initialize the WebSocket server.
        
        Args:
            model_path: Path to the YOLO model weights
            host: Host address to bind the server
            port: Port to bind the server
            device: Device to run inference on (0 for first GPU, 'cpu' for CPU)
        """
        self.host = host
        self.port = port
        self.yolo_model = YoloModel(model_path, device)
        self.clients = set()
        logger.info(f"Server initialized on {host}:{port}")
    
    async def register(self, websocket):
        """Register a new client."""
        self.clients.add(websocket)
        logger.info(f"Client connected. Total clients: {len(self.clients)}")
    
    async def unregister(self, websocket):
        """Unregister a client."""
        if websocket in self.clients:
            self.clients.remove(websocket)
            logger.info(f"Client disconnected. Total clients: {len(self.clients)}")
    
    async def process_image(self, image_data: str, conf: float = 0.25) -> Dict[str, Any]:
        """
        Process a base64 encoded image.
        
        Args:
            image_data: Base64 encoded image string
            conf: Confidence threshold for detections
            
        Returns:
            Detection results
        """
        try:
            # Decode base64 image
            image_bytes = base64.b64decode(image_data)
            nparr = np.frombuffer(image_bytes, np.uint8)
            
            # Log the exact size to help with debugging
            logger.info(f"Raw image data size: {len(nparr)} bytes")
            
            # Try standard image decoders first
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                image = cv2.imdecode(nparr, cv2.IMREAD_UNCHANGED)
                
            if image is None:
                # For YUV data with size 368592, most likely a 496x496 image
                # For YUV420 format, calculate dimensions: size = width*height*3/2
                
                size = len(nparr)
                # Try to create a grayscale image from the Y plane data
                # We'll assume that the first 2/3 of the data is the Y plane
                
                # Calculate reasonable dimensions for the data size
                dim = int(np.sqrt(size * 2/3))
                dim = dim - (dim % 2)  # Ensure even dimensions for YUV
                
                # Create a grayscale image from first width*height bytes (Y plane)
                try:
                    y_size = dim * dim
                    if len(nparr) >= y_size:
                        # Extract Y plane and create a grayscale image
                        y_plane = nparr[:y_size].reshape(dim, dim)
                        image = cv2.cvtColor(y_plane, cv2.COLOR_GRAY2RGB)
                        logger.info(f"Created grayscale image from Y plane: {dim}x{dim}")
                except Exception as e:
                    logger.error(f"Failed to create Y plane image: {e}")
                    
                    # Create a dummy image as last resort
                    dummy_width, dummy_height = 320, 240
                    logger.warning(f"Creating dummy test image of size {dummy_width}x{dummy_height}")
                    image = np.zeros((dummy_height, dummy_width, 3), dtype=np.uint8)
                    cv2.putText(image, "Image Decode Error", (10, dummy_height//2), 
                                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 0, 0), 2)
            
            # Run YOLO detection
            results = self.yolo_model.detect_objects(image, conf=conf)
            
            # Process results to a format suitable for JSON
            processed_results = self.yolo_model.process_results(results)
            
            processed_results["image_dims"] = {
                "height": image.shape[0],
                "width": image.shape[1],
                "channels": image.shape[2] if len(image.shape) > 2 else 1
            }
            
            return processed_results
            
        except Exception as e:
            logger.error(f"Image processing error: {str(e)}")
            # Log sample data for debugging
            sample = image_data[:100] + "..." if len(image_data) > 100 else image_data
            logger.debug(f"Image data sample: {sample}")
            raise
         
    async def handle_client(self, websocket):
        """Handle websocket connections."""
        await self.register(websocket)
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    
                    if not isinstance(data, dict) or "type" not in data:
                        await websocket.send(json.dumps({"error": "Invalid message format"}))
                        continue
                    
                    # Handle different message types
                    if data["type"] == "image":
                        if "data" not in data:
                            await websocket.send(json.dumps({"error": "Missing image data"}))
                            continue
                            
                        start_time = datetime.now()
                        conf_threshold = data.get("conf", 0.25)
                        
                        # Extract image format and dimensions if available
                        image_format = data.get("format", "unknown")
                        image_width = data.get("width", 0)
                        image_height = data.get("height", 0)
                        
                        logger.info(f"Received image: format={image_format}, dimensions={image_width}x{image_height}")
                        
                        try:
                            # Update process_image method signature to accept format and dimensions
                            detection_results = await self.process_image(
                                data["data"], 
                                conf=conf_threshold
                            )
                            
                            processing_time = (datetime.now() - start_time).total_seconds() * 1000
                            detection_results["processing_time_ms"] = round(processing_time, 2)
                            
                            await websocket.send(json.dumps(detection_results))
                        except Exception as e:
                            error_msg = f"Image processing error: {str(e)}"
                            logger.error(error_msg)
                            await websocket.send(json.dumps({"error": error_msg}))
                        
                    elif data["type"] == "config":
                        if "model_path" in data:
                            try:
                                self.yolo_model = YoloModel(data["model_path"], self.yolo_model.device)
                                await websocket.send(json.dumps({"status": "success", "message": "Model reloaded"}))
                            except Exception as e:
                                await websocket.send(json.dumps({"status": "error", "message": str(e)}))
                    
                    else:
                        await websocket.send(json.dumps({"error": "Unknown message type"}))
                        
                except json.JSONDecodeError:
                    await websocket.send(json.dumps({"error": "Invalid JSON"}))
                except Exception as e:
                    logger.error(f"Error handling message: {e}")
                    await websocket.send(json.dumps({"error": str(e)}))
                    
        except websockets.exceptions.ConnectionClosed as e:
            logger.info(f"Connection closed: {e}")
        except Exception as e:
            logger.error(f"Unexpected error in client handler: {e}")
        finally:
            await self.unregister(websocket)
    
    async def start_server(self):
        """Start the WebSocket server."""
        try:
             # Bind the handle_client method to the instance
            handler = functools.partial(self.handle_client)
            server = await websockets.serve(
                self.handle_client, 
                self.host, 
                self.port,
                ping_interval=20,  # Send ping every 20 seconds
                ping_timeout=30,   # Close if no pong after 30s
                close_timeout=10  # Wait 10s for proper close
            )
            logger.info(f"Server started on ws://{self.host}:{self.port}")
            await server.wait_closed()
        except Exception as e:
            logger.error(f"Failed to start server: {e}")
            raise

async def main():
    """Main function to start the server."""
    import argparse
    import os
    
    # Define the absolute path to the custom model
    current_dir = os.path.dirname(os.path.abspath(__file__))
    default_model_path = os.path.join(current_dir, 'yoloe-v8s-seg-pf.pt')
    
    # Verify model exists
    if not os.path.exists(default_model_path):
        logger.error(f"Custom model not found at: {default_model_path}")
        logger.info("Available models in the directory:")
        for file in os.listdir(current_dir):
            if file.endswith(('.pt', '.pth', '.weights')):
                logger.info(f"  - {file}")
    else:
        logger.info(f"Found custom model at: {default_model_path}")
    
    parser = argparse.ArgumentParser(description='YOLO WebSocket Server')
    parser.add_argument('--model', type=str, default=default_model_path,
                      help='Path to YOLO model weights')
    parser.add_argument('--host', type=str, default='0.0.0.0',
                      help='Host to bind server to')
    parser.add_argument('--port', type=int, default=8765,
                      help='Port to bind server to')
    parser.add_argument('--device', type=str, default='0',
                      help='Device to run inference on (0, 1, etc. for GPU, or "cpu")')
    
    args = parser.parse_args()
    
    # Convert device to proper format
    device = args.device
    if device.isdigit():
        device = int(device)
    
    # Double check model file
    if not os.path.exists(args.model):
        logger.error(f"ERROR: Model file not found at {args.model}")
        raise FileNotFoundError(f"Model file not found: {args.model}")
    
    logger.info(f"Starting server with model: {args.model}")
    
    # Force model reload if needed
    if 'YOLO' in locals():
        logger.info("Clearing existing YOLO models from memory")
        import gc
        gc.collect()
        torch.cuda.empty_cache() if torch.cuda.is_available() else None
    
    # Start server
    server = YoloWebsocketServer(
        model_path=args.model,
        host=args.host,
        port=args.port,
        device=device
    )
    
    try:
        await server.start_server()
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")

if __name__ == "__main__":
    asyncio.run(main())