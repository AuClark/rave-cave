#!/usr/bin/env python3
"""
Hardware probing for Raspberry Pi Model A+ with RGB Matrix Bonnet and Pi Camera.

Checks:
- Pi model from device tree
- HAT/Bonnet detection (EEPROM via i2c, device tree)
- Camera detection via picamera2 or rpicam-hello
"""

import os
import subprocess
import json
from typing import Dict, Any, Optional


def get_pi_model() -> str:
    """Read Pi model from device tree."""
    try:
        with open('/proc/device-tree/model', 'r') as f:
            return f.read().strip('\x00').strip()
    except FileNotFoundError:
        return "Unknown (not a Pi or /proc/device-tree/model missing)"
    except Exception as e:
        return f"Error reading model: {e}"


def get_hat_info() -> Dict[str, Any]:
    """
    Probe for HAT/Bonnet via device tree and i2c EEPROM.
    
    Note: Adafruit RGB Matrix Bonnet (ADA3211) may not have HAT EEPROM,
    so detection is best-effort. Later we'll check GPIO usage when
    rpi-rgb-led-matrix is running.
    """
    info = {
        'detected': False,
        'source': None,
        'details': {}
    }
    
    # Check device tree HAT node
    hat_path = '/proc/device-tree/hat'
    if os.path.isdir(hat_path):
        try:
            details = {}
            for field in ['product', 'vendor', 'product_id', 'product_ver']:
                fpath = os.path.join(hat_path, field)
                if os.path.isfile(fpath):
                    with open(fpath, 'r') as f:
                        details[field] = f.read().strip('\x00').strip()
            
            if details:
                info['detected'] = True
                info['source'] = 'device-tree'
                info['details'] = details
                return info
        except Exception as e:
            info['details']['dt_error'] = str(e)
    
    # Try i2c EEPROM at 0x50 on bus 1
    # HAT spec: 24C32 or similar at 0x50, but Bonnet may not have it
    try:
        result = subprocess.run(
            ['i2cdetect', '-y', '1'],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode == 0 and '50' in result.stdout:
            info['detected'] = True
            info['source'] = 'i2c-0x50'
            info['details']['note'] = 'HAT EEPROM present at 0x50'
        else:
            info['details']['i2c_scan'] = 'No EEPROM at 0x50 (expected for Adafruit Bonnet)'
    except FileNotFoundError:
        info['details']['i2c_error'] = 'i2cdetect not found (install i2c-tools)'
    except subprocess.TimeoutExpired:
        info['details']['i2c_error'] = 'i2cdetect timeout'
    except Exception as e:
        info['details']['i2c_error'] = str(e)
    
    return info


def get_camera_info() -> Dict[str, Any]:
    """
    Probe for Pi Camera via picamera2 or rpicam-hello.
    
    Supports libcamera stack (Bookworm default).
    """
    info = {
        'detected': False,
        'source': None,
        'details': {}
    }
    
    # Try picamera2 first (Python API)
    try:
        from picamera2 import Picamera2
        cameras = Picamera2.global_camera_info()
        if cameras:
            info['detected'] = True
            info['source'] = 'picamera2'
            info['details']['cameras'] = cameras
            return info
    except ImportError:
        info['details']['picamera2'] = 'not installed'
    except Exception as e:
        info['details']['picamera2_error'] = str(e)
    
    # Fallback: rpicam-hello --list-cameras
    try:
        result = subprocess.run(
            ['rpicam-hello', '--list-cameras', '--timeout', '0'],
            capture_output=True,
            text=True,
            timeout=3
        )
        if result.returncode == 0 and result.stdout:
            # Parse output for "Available cameras"
            if 'Available cameras' in result.stdout or 'imx' in result.stdout.lower() or 'ov5647' in result.stdout.lower():
                info['detected'] = True
                info['source'] = 'rpicam-hello'
                info['details']['output'] = result.stdout.strip()
            else:
                info['details']['rpicam-hello'] = 'No cameras found'
        else:
            info['details']['rpicam-hello'] = result.stderr.strip() if result.stderr else 'Failed'
    except FileNotFoundError:
        info['details']['rpicam_error'] = 'rpicam-hello not found (install libcamera-apps)'
    except subprocess.TimeoutExpired:
        info['details']['rpicam_error'] = 'rpicam-hello timeout'
    except Exception as e:
        info['details']['rpicam_error'] = str(e)
    
    return info


def get_uptime() -> str:
    """Get system uptime string."""
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.read().split()[0])
            days = int(uptime_seconds // 86400)
            hours = int((uptime_seconds % 86400) // 3600)
            minutes = int((uptime_seconds % 3600) // 60)
            if days > 0:
                return f"{days}d {hours}h {minutes}m"
            elif hours > 0:
                return f"{hours}h {minutes}m"
            else:
                return f"{minutes}m"
    except Exception as e:
        return f"Error: {e}"


def get_memory_info() -> Dict[str, Any]:
    """Get memory usage from /proc/meminfo."""
    try:
        mem = {}
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if line.startswith('MemTotal:'):
                    mem['total_kb'] = int(line.split()[1])
                elif line.startswith('MemAvailable:'):
                    mem['available_kb'] = int(line.split()[1])
                elif line.startswith('MemFree:'):
                    mem['free_kb'] = int(line.split()[1])
        
        if 'total_kb' in mem and 'available_kb' in mem:
            mem['used_kb'] = mem['total_kb'] - mem['available_kb']
            mem['used_pct'] = round((mem['used_kb'] / mem['total_kb']) * 100, 1)
        
        return mem
    except Exception as e:
        return {'error': str(e)}


def get_hostname() -> str:
    """Get system hostname."""
    try:
        with open('/etc/hostname', 'r') as f:
            return f.read().strip()
    except Exception:
        return os.uname().nodename


if __name__ == '__main__':
    # Test hardware probing
    print("=== Pi Model ===")
    print(get_pi_model())
    print("\n=== HAT/Bonnet Info ===")
    print(json.dumps(get_hat_info(), indent=2))
    print("\n=== Camera Info ===")
    print(json.dumps(get_camera_info(), indent=2))
    print("\n=== System Info ===")
    print(f"Hostname: {get_hostname()}")
    print(f"Uptime: {get_uptime()}")
    print(f"Memory: {json.dumps(get_memory_info(), indent=2)}")
