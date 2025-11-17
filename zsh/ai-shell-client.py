#!/usr/bin/env python3
"""
AI Shell Client - Helper for ZSH integration
Sends requests to the AI Shell daemon via Unix socket
"""

import socket
import json
import struct
import sys

def send_request(socket_path, request_json):
    """Send a request and return the response"""
    try:
        # Create socket
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(socket_path)

        # Encode request
        request_bytes = request_json.encode('utf-8')

        # Create length prefix (4 bytes, big-endian)
        length = len(request_bytes)
        length_prefix = struct.pack('>I', length)

        # Send length-prefixed message
        sock.sendall(length_prefix + request_bytes)

        # Read response length prefix
        response_length_bytes = sock.recv(4)
        if len(response_length_bytes) < 4:
            return None

        response_length = struct.unpack('>I', response_length_bytes)[0]

        # Read response body
        response_bytes = b''
        while len(response_bytes) < response_length:
            chunk = sock.recv(response_length - len(response_bytes))
            if not chunk:
                break
            response_bytes += chunk

        if len(response_bytes) < response_length:
            return None

        # Return response as string
        return response_bytes.decode('utf-8')

    except Exception:
        return None
    finally:
        try:
            sock.close()
        except:
            pass

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: ai-shell-client.py <socket_path> <json_request>", file=sys.stderr)
        sys.exit(1)

    socket_path = sys.argv[1]
    request_json = sys.argv[2]

    response = send_request(socket_path, request_json)
    if response:
        print(response)
        sys.exit(0)
    else:
        sys.exit(1)
