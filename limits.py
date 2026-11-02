"""Print the Claude or Codex usage windows as JSON. Reads usage only, never prints credentials.

Usage: py -3 limits.py claude|codex
"""
import ctypes
from datetime import datetime
import json
from pathlib import Path
import socket
import struct
import sys
import time
import urllib.request


def window(value, percent_key, reset_key, minutes):
    if not isinstance(value, dict):
        return None
    percent, reset = value.get(percent_key), value.get(reset_key)
    if not isinstance(percent, (int, float)) or isinstance(percent, bool) or not 0 <= percent <= 100:
        return None
    if isinstance(reset, str):
        reset = datetime.fromisoformat(reset.replace('Z', '+00:00')).timestamp()
    return {'usedPercent': percent, 'resetsAt': reset if isinstance(reset, (int, float)) else None,
            'windowMinutes': minutes}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def claude_limits():
    credentials = json.loads((Path.home()/'.claude/.credentials.json').read_text(encoding='utf-8'))
    token = credentials.get('claudeAiOauth', {}).get('accessToken')
    if not token:
        raise OSError('Claude sign-in unavailable')
    request = urllib.request.Request('https://api.anthropic.com/api/oauth/usage', headers={
        'Authorization': 'Bearer ' + token, 'anthropic-beta': 'oauth-2025-04-20',
        'User-Agent': 'usage-limits-tray/1.0'})
    with urllib.request.build_opener(NoRedirect).open(request, timeout=8) as response:
        data = json.load(response)
    return {'primary': window(data.get('five_hour'), 'utilization', 'resets_at', 300),
            'secondary': window(data.get('seven_day'), 'utilization', 'resets_at', 10080)}


class WindowsLocalSocket(socket.socket):
    def setsockopt(self, level, option, value):
        # AF_UNIX has no TCP_NODELAY; websockets enables it unconditionally.
        if level == socket.IPPROTO_TCP and option == socket.TCP_NODELAY:
            return
        return super().setsockopt(level, option, value)


def codex_socket():
    # Python has no socket.AF_UNIX on Windows, so open the daemon's control socket via Winsock.
    path = str(Path.home()/'.codex/app-server-control/app-server-control.sock').encode('utf-8')
    if len(path) >= 108:
        raise ValueError('Local socket path too long')
    library = ctypes.WinDLL('ws2_32')
    library.socket.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
    library.socket.restype = ctypes.c_size_t
    library.connect.argtypes = [ctypes.c_size_t, ctypes.c_void_p, ctypes.c_int]
    library.connect.restype = ctypes.c_int
    library.closesocket.argtypes = [ctypes.c_size_t]
    handle = library.socket(1, 1, 0)
    if handle == ctypes.c_size_t(-1).value:
        raise OSError('Local socket unavailable')
    address = ctypes.create_string_buffer(struct.pack('H', 1) + path + b'\0' * (108 - len(path)))
    if library.connect(handle, address, 110):
        library.closesocket(handle)
        raise OSError('Codex daemon unavailable')
    try:
        return WindowsLocalSocket(fileno=handle)
    except Exception:
        library.closesocket(handle)
        raise


def codex_limits():
    from websockets.sync.client import connect
    sock = codex_socket()
    try:
        with connect('ws://localhost', sock=sock, open_timeout=3, close_timeout=1) as connection:
            def request(identifier, method, params):
                connection.send(json.dumps({'id': identifier, 'method': method, 'params': params}))
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    response = json.loads(connection.recv(timeout=max(.1, deadline-time.monotonic())))
                    if response.get('id') == identifier:
                        if 'error' in response:
                            raise OSError('Usage unavailable')
                        return response['result']
                raise TimeoutError('Usage timeout')
            request(1, 'initialize', {'clientInfo': {'name': 'usage_limits_tray', 'version': '1.0'}})
            connection.send(json.dumps({'method': 'initialized', 'params': {}}))
            response = request(2, 'account/rateLimits/read', {})
            limits = response.get('rateLimitsByLimitId', {}).get('codex') or response.get('rateLimits') or {}
            return {key: window(limits.get(key), 'usedPercent', 'resetsAt', (limits.get(key) or {}).get('windowDurationMins'))
                    for key in ('primary', 'secondary')}
    finally:
        sock.close()


if __name__ == '__main__':
    limits = {'claude': claude_limits, 'codex': codex_limits}[sys.argv[1]]()
    if not any(limits.values()):
        sys.exit('No usage windows')
    print(json.dumps(limits))
