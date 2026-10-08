#!/usr/bin/env python3
"""Control an LG webOS TV over a direct Ethernet link.

Usage: tvctl.py on|off|pair|status [reason]
"""
import base64, datetime, json, os, socket, ssl, struct, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
CFG = json.load(open(os.path.join(HERE, "config.json")))
KEY_FILE = os.path.join(HERE, "client-key")
LOG = os.path.expanduser("~/Library/Logs/lg-tv-wake.log")
PORT = 3001
PERMISSIONS = ["LAUNCH", "CONTROL_POWER", "READ_POWER_STATE", "CONTROL_INPUT_TV",
               "READ_INPUT_DEVICE_LIST", "CONTROL_AUDIO", "CONTROL_DISPLAY"]


def log(msg):
    with open(LOG, "a") as f:
        f.write(f"{datetime.datetime.now():%F %T} {msg}\n")


def iface_ready():
    out = subprocess.run(["ifconfig", CFG["iface"]], capture_output=True, text=True).stdout
    return "status: active" in out and f"inet {CFG['mac_ip']} " in out


def power_on():
    # Wake-on-LAN: works while the TV is in Quick Start+ standby.
    for _ in range(60):
        if iface_ready():
            break
        time.sleep(0.5)
    else:
        raise RuntimeError(f"{CFG['iface']} not ready")
    packet = b"\xff" * 6 + bytes.fromhex(CFG["tv_mac"].replace(":", "")) * 16
    bcast = CFG["mac_ip"].rsplit(".", 1)[0] + ".255"
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.bind((CFG["mac_ip"], 0))
    for _ in range(5):
        for port in (9, 7):
            s.sendto(packet, (bcast, port))
        time.sleep(0.5)


class WS:
    """Minimal websocket client for the TV's SSAP API."""

    def __init__(self, timeout):
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE  # TV uses a self-signed cert
        raw = socket.create_connection((CFG["tv_ip"], PORT), timeout=timeout)
        self.s = ctx.wrap_socket(raw, server_hostname=CFG["tv_ip"])
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall((f"GET / HTTP/1.1\r\nHost: {CFG['tv_ip']}:{PORT}\r\nUpgrade: websocket\r\n"
                        f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
                        "Sec-WebSocket-Version: 13\r\n\r\n").encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            chunk = self.s.recv(1024)
            if not chunk:
                raise ConnectionError("handshake closed")
            resp += chunk
        if b" 101 " not in resp.split(b"\r\n")[0]:
            raise ConnectionError(resp.split(b"\r\n")[0].decode())

    def send(self, obj):
        data = json.dumps(obj).encode()
        n = len(data)
        hdr = bytes([0x81])
        if n < 126:
            hdr += bytes([0x80 | n])
        elif n < 65536:
            hdr += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            hdr += bytes([0x80 | 127]) + struct.pack(">Q", n)
        mask = os.urandom(4)
        self.s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def _exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.s.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("closed")
            buf += chunk
        return buf

    def recv(self):
        while True:
            b1, b2 = self._exact(2)
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._exact(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._exact(8))[0]
            payload = self._exact(n)
            if b1 & 0x0F == 1:
                return json.loads(payload)
            if b1 & 0x0F == 8:
                raise ConnectionError("closed by TV")


def connect(pairing=False):
    # The USB Ethernet link can drop briefly around display sleep, so retry.
    deadline = time.time() + 15
    while True:
        try:
            ws = WS(timeout=60 if pairing else 5)
            break
        except OSError:
            if time.time() > deadline:
                raise
            time.sleep(1)
    payload = {"forcePairing": False, "pairingType": "PROMPT",
               "manifest": {"manifestVersion": 1, "appVersion": "1.0", "permissions": PERMISSIONS}}
    if os.path.exists(KEY_FILE):
        payload["client-key"] = open(KEY_FILE).read().strip()
    ws.send({"type": "register", "id": "reg0", "payload": payload})
    while True:
        msg = ws.recv()
        if msg.get("type") == "registered":
            with open(KEY_FILE, "w") as f:
                f.write(msg["payload"]["client-key"])
            os.chmod(KEY_FILE, 0o600)
            return ws
        if msg.get("type") == "error":
            raise RuntimeError(msg.get("error"))


def request(ws, uri):
    ws.send({"type": "request", "id": "req1", "uri": uri, "payload": {}})
    while True:
        msg = ws.recv()
        if msg.get("id") == "req1":
            return msg.get("payload")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    reason = sys.argv[2] if len(sys.argv) > 2 else "manual"
    try:
        if cmd == "on":
            power_on()
        elif cmd == "off":
            request(connect(), "ssap://system/turnOff")
        elif cmd == "pair":
            connect(pairing=True)
            print("paired")
        elif cmd == "status":
            print(request(connect(), "ssap://com.webos.service.tvpower/power/getPowerState"))
            return
        else:
            sys.exit(__doc__)
        log(f"{cmd.upper()} ok ({reason})")
    except Exception as e:
        log(f"{cmd.upper()} failed ({reason}): {e}")
        raise


if __name__ == "__main__":
    main()
