#!/usr/bin/env python3
"""
Rave Cave Panel Controller Web Server

Simple Flask app for monitoring Raspberry Pi 3 Model A+ with RGB Matrix Bonnet
and Pi Camera. Serves live camera feed and hardware status.

Endpoints:
- GET /              : Status page with live MJPEG feed
- GET /api/status    : JSON hardware/system status
- GET /stream.mjpg   : MJPEG camera stream
"""

import io
import time
import logging
from threading import Thread, Lock
from flask import Flask, Response, jsonify, render_template_string
import hw

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Camera state
camera_lock = Lock()
camera_frame = None
camera_error = None


def init_camera():
    """Initialize picamera2 if available."""
    global camera_frame, camera_error
    try:
        from picamera2 import Picamera2
        from picamera2.encoders import JpegEncoder
        from picamera2.outputs import FileOutput
        
        logger.info("Initializing camera...")
        picam2 = Picamera2()
        
        # Configure for streaming: 640x480 MJPEG
        config = picam2.create_video_configuration(
            main={"size": (640, 480), "format": "RGB888"}
        )
        picam2.configure(config)
        picam2.start()
        
        logger.info("Camera started successfully")
        return picam2
    except ImportError:
        camera_error = "picamera2 not installed (pip3 install picamera2)"
        logger.error(camera_error)
        return None
    except Exception as e:
        camera_error = f"Camera init failed: {e}"
        logger.error(camera_error)
        return None


def camera_thread():
    """Background thread to capture camera frames."""
    global camera_frame, camera_error
    
    picam2 = init_camera()
    if not picam2:
        return
    
    try:
        while True:
            try:
                # Capture frame as JPEG
                frame = picam2.capture_array()
                from PIL import Image
                img = Image.fromarray(frame)
                
                # Convert to JPEG bytes
                buf = io.BytesIO()
                img.save(buf, format='JPEG', quality=85)
                jpeg_bytes = buf.getvalue()
                
                with camera_lock:
                    camera_frame = jpeg_bytes
                
                time.sleep(0.033)  # ~30 fps
            except Exception as e:
                logger.error(f"Frame capture error: {e}")
                time.sleep(1)
    finally:
        if picam2:
            picam2.stop()


def generate_mjpeg():
    """Generate MJPEG stream from camera frames."""
    global camera_frame, camera_error
    
    if camera_error:
        # Return error image
        yield b'--frame\r\n'
        yield b'Content-Type: text/plain\r\n\r\n'
        yield f"Camera unavailable: {camera_error}".encode()
        return
    
    while True:
        with camera_lock:
            if camera_frame is None:
                # Camera not ready yet
                time.sleep(0.1)
                continue
            frame = camera_frame
        
        yield b'--frame\r\n'
        yield b'Content-Type: image/jpeg\r\n\r\n'
        yield frame
        yield b'\r\n'
        time.sleep(0.033)  # ~30 fps


@app.route('/')
def index():
    """Status page with live camera feed."""
    # Dark-themed HTML with embedded MJPEG stream
    html = """
<!DOCTYPE html>
<html>
<head>
    <title>Rave Cave Panel Controller</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Monaco', 'Courier New', monospace;
            background: #0a0a0a;
            color: #00ff00;
            padding: 20px;
            line-height: 1.6;
        }
        h1 {
            color: #ff00ff;
            margin-bottom: 20px;
            text-shadow: 0 0 10px #ff00ff;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .section {
            background: #1a1a1a;
            border: 2px solid #333;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .section h2 {
            color: #00ffff;
            margin-bottom: 15px;
            text-shadow: 0 0 5px #00ffff;
        }
        .stream-container {
            background: #000;
            border: 2px solid #ff00ff;
            border-radius: 8px;
            padding: 10px;
            text-align: center;
        }
        .stream-container img {
            max-width: 100%;
            height: auto;
            border-radius: 4px;
        }
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
            margin-top: 15px;
        }
        .status-item {
            background: #0d0d0d;
            padding: 12px;
            border-left: 3px solid #00ff00;
            border-radius: 4px;
        }
        .status-item.warning { border-left-color: #ffaa00; }
        .status-item.error { border-left-color: #ff0000; }
        .label { color: #888; font-size: 0.9em; }
        .value { color: #00ff00; font-weight: bold; margin-top: 5px; }
        .footer {
            text-align: center;
            color: #555;
            margin-top: 30px;
            font-size: 0.9em;
        }
        .refresh-btn {
            background: #ff00ff;
            color: #000;
            border: none;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            font-family: inherit;
            font-weight: bold;
            margin-top: 10px;
        }
        .refresh-btn:hover { background: #ff66ff; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎛️ Rave Cave Panel Controller</h1>
        
        <div class="section">
            <h2>📹 Live Camera Feed</h2>
            <div class="stream-container">
                <img src="/stream.mjpg" alt="Camera Stream" onerror="this.src='/static/error.jpg'; this.onerror=null;">
            </div>
        </div>
        
        <div class="section">
            <h2>🔧 Hardware Status</h2>
            <div class="status-grid" id="status-grid">
                <div class="status-item"><div class="label">Loading...</div></div>
            </div>
            <button class="refresh-btn" onclick="loadStatus()">Refresh Status</button>
        </div>
        
        <div class="footer">
            Rave Cave • rave-box • <a href="/api/status" style="color: #555;">JSON API</a>
        </div>
    </div>
    
    <script>
        function loadStatus() {
            fetch('/api/status')
                .then(r => r.json())
                .then(data => {
                    const grid = document.getElementById('status-grid');
                    grid.innerHTML = '';
                    
                    // Hostname
                    grid.innerHTML += `
                        <div class="status-item">
                            <div class="label">Hostname</div>
                            <div class="value">${data.hostname}</div>
                        </div>
                    `;
                    
                    // Model
                    grid.innerHTML += `
                        <div class="status-item">
                            <div class="label">Pi Model</div>
                            <div class="value">${data.model}</div>
                        </div>
                    `;
                    
                    // Camera
                    const camClass = data.camera.detected ? 'status-item' : 'status-item error';
                    const camStatus = data.camera.detected ? '✓ Detected' : '✗ Not Found';
                    grid.innerHTML += `
                        <div class="${camClass}">
                            <div class="label">Camera</div>
                            <div class="value">${camStatus}</div>
                            <div class="label" style="margin-top: 5px;">${data.camera.source || 'N/A'}</div>
                        </div>
                    `;
                    
                    // Bonnet/HAT
                    const hatClass = data.bonnet.detected ? 'status-item' : 'status-item warning';
                    const hatStatus = data.bonnet.detected ? '✓ Detected' : '? Best-effort';
                    grid.innerHTML += `
                        <div class="${hatClass}">
                            <div class="label">RGB Matrix Bonnet</div>
                            <div class="value">${hatStatus}</div>
                            <div class="label" style="margin-top: 5px;">${data.bonnet.source || 'No EEPROM (expected)'}</div>
                        </div>
                    `;
                    
                    // Uptime
                    grid.innerHTML += `
                        <div class="status-item">
                            <div class="label">Uptime</div>
                            <div class="value">${data.uptime}</div>
                        </div>
                    `;
                    
                    // Memory
                    const memPct = data.memory.used_pct || 0;
                    const memClass = memPct > 80 ? 'status-item warning' : 'status-item';
                    grid.innerHTML += `
                        <div class="${memClass}">
                            <div class="label">Memory</div>
                            <div class="value">${memPct}% used</div>
                            <div class="label" style="margin-top: 5px;">${(data.memory.used_kb/1024).toFixed(0)} / ${(data.memory.total_kb/1024).toFixed(0)} MB</div>
                        </div>
                    `;
                })
                .catch(err => {
                    console.error('Status fetch error:', err);
                    document.getElementById('status-grid').innerHTML = '<div class="status-item error"><div class="value">Error loading status</div></div>';
                });
        }
        
        // Load status on page load and every 10 seconds
        loadStatus();
        setInterval(loadStatus, 10000);
    </script>
</body>
</html>
    """
    return render_template_string(html)


@app.route('/api/status')
def api_status():
    """JSON API endpoint for hardware status."""
    try:
        status = {
            'hostname': hw.get_hostname(),
            'model': hw.get_pi_model(),
            'camera': hw.get_camera_info(),
            'bonnet': hw.get_hat_info(),
            'uptime': hw.get_uptime(),
            'memory': hw.get_memory_info(),
            'timestamp': int(time.time())
        }
        return jsonify(status)
    except Exception as e:
        logger.error(f"Status API error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/stream.mjpg')
def stream():
    """MJPEG stream endpoint."""
    return Response(
        generate_mjpeg(),
        mimetype='multipart/x-mixed-replace; boundary=frame'
    )


if __name__ == '__main__':
    # Start camera thread
    camera_bg = Thread(target=camera_thread, daemon=True)
    camera_bg.start()
    
    logger.info("Starting Rave Cave Panel Controller on 0.0.0.0:8080")
    logger.info("Camera status will be available at http://rave-box.local:8080/")
    
    # Run Flask app
    app.run(host='0.0.0.0', port=8080, debug=False, threaded=True)
