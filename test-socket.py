#!/usr/bin/env python3
"""Simple test client for AI Shell Daemon"""

import socket
import json
import struct
import sys

def send_request(socket_path, request):
    """Send a request to the daemon and print the response"""

    # Create socket
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

    try:
        # Connect
        sock.connect(socket_path)
        print(f"✓ Connected to {socket_path}")

        # Encode request as JSON
        request_json = json.dumps(request)
        request_bytes = request_json.encode('utf-8')

        # Create length prefix (4 bytes, big-endian)
        length = len(request_bytes)
        length_prefix = struct.pack('>I', length)

        # Send length-prefixed message
        sock.sendall(length_prefix + request_bytes)
        print(f"✓ Sent request ({length} bytes)")

        # Read response length prefix (4 bytes)
        response_length_bytes = sock.recv(4)
        if len(response_length_bytes) < 4:
            print("✗ Failed to read response length")
            return None

        response_length = struct.unpack('>I', response_length_bytes)[0]
        print(f"✓ Response length: {response_length} bytes")

        # Read response body
        response_bytes = b''
        while len(response_bytes) < response_length:
            chunk = sock.recv(response_length - len(response_bytes))
            if not chunk:
                break
            response_bytes += chunk

        if len(response_bytes) < response_length:
            print(f"✗ Incomplete response: got {len(response_bytes)}/{response_length} bytes")
            return None

        # Decode response
        response_json = response_bytes.decode('utf-8')
        response = json.loads(response_json)

        print("✓ Received response:")
        print(json.dumps(response, indent=2))

        return response

    except Exception as e:
        print(f"✗ Error: {e}")
        return None

    finally:
        sock.close()

def test_health():
    """Test health check"""
    print("\n=== Testing Health Check ===")

    request = {
        "id": "test-health-001",
        "type": "health",
        "payload": {},
        "timestamp": "2025-11-17T23:30:00Z"
    }

    return send_request("/tmp/ai-shell.sock", request)

def test_task():
    """Test task conversion"""
    print("\n=== Testing Task Conversion ===")

    request = {
        "id": "test-task-001",
        "type": "task",
        "payload": {
            "task": "list all Swift files in current directory",
            "workingDirectory": "~/projects",
            "context": {
                "history": [],
                "gitBranch": "main",
                "environment": {
                    "SHELL": "/bin/zsh",
                    "USER": "test",
                    "PWD": "~/projects"
                }
            }
        },
        "timestamp": "2025-11-17T23:30:00Z"
    }

    return send_request("/tmp/ai-shell.sock", request)

if __name__ == "__main__":
    print("AI Shell Daemon - Socket Test Client")
    print("=" * 50)

    # Test health check
    health_result = test_health()

    if health_result and health_result.get('status') == 'success':
        print("\n✓ Daemon is healthy!")

        # Test task conversion
        if len(sys.argv) > 1 and sys.argv[1] == "--full":
            task_result = test_task()
    else:
        print("\n✗ Daemon health check failed")
        sys.exit(1)
