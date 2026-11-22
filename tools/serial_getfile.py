#!/usr/bin/env python3
"""Fetch a file from the serial console target (base64) with md5 verify.

Usage: serial_getfile.py --port /dev/ttyUSB0 --baud 1500000 --remote /path/on/target --out /local/path
"""
import argparse
import base64
import hashlib
import os
import re
import select
import sys
import termios
import time

B64LINE = re.compile(rb"^[A-Za-z0-9+/]+={0,2}$")


def open_port(path, baud):
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[0] = 0
    a[1] = 0
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    a[3] = 0
    a[4] = getattr(termios, "B%s" % baud)
    a[5] = getattr(termios, "B%s" % baud)
    a[6][termios.VMIN] = 0
    a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


def drain(fd, dur, quiet_stop=None):
    buf = b""
    t0 = time.time()
    last = t0
    while True:
        now = time.time()
        if now - t0 >= dur:
            break
        if quiet_stop is not None and now - last >= quiet_stop:
            break
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                c = os.read(fd, 65536)
            except OSError:
                break
            if c:
                buf += c
                last = time.time()
    return buf


def wait_for(fd, needle, timeout):
    needle = needle.encode() if isinstance(needle, str) else needle
    buf = b""
    t0 = time.time()
    while time.time() - t0 < timeout:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                buf += os.read(fd, 65536)
            except OSError:
                break
            if needle in buf:
                return True, buf
    return False, buf


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", default="/dev/ttyUSB0")
    p.add_argument("--baud", type=int, default=1500000)
    p.add_argument("--remote", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--user", default="root")
    p.add_argument("--password", default=os.environ.get("SERIAL_PASSWORD", ""))
    p.add_argument("--timeout", type=float, default=180.0)
    args = p.parse_args()

    fd = open_port(args.port, args.baud)
    try:
        drain(fd, 0.5)
        os.write(fd, b"\r")
        out = drain(fd, 1.5, quiet_stop=0.8)
        if b"login:" in out:
            os.write(fd, (args.user + "\r").encode())
            ok, _ = wait_for(fd, "assword", 5)
            if ok:
                os.write(fd, (args.password + "\r").encode())
                drain(fd, 2.0, quiet_stop=1.0)

        os.write(fd, b"stty -echo\r")
        drain(fd, 0.4)
        os.write(fd, ("md5sum %s\r" % args.remote).encode())
        ok, out = wait_for(fd, b"\n", 5)
        out += drain(fd, 2.0, quiet_stop=1.0)
        text = out.decode("utf-8", "replace")
        # md5sum prints "<hash>  <path>"; OSC/log noise may contain other hex
        hashes = re.findall(r"[0-9a-f]{32}", text)
        remote_md5 = hashes[-1] if hashes else ""
        print("remote md5:", remote_md5 or "(not parsed)")

        os.write(fd, ("echo GBEGIN_ZX9; base64 -w 76 %s; echo; echo GEND_ZX9\r"
                      % args.remote).encode())
        buf = b""
        t0 = time.time()
        while time.time() - t0 < args.timeout:
            r, _, _ = select.select([fd], [], [], 0.2)
            if r:
                try:
                    buf += os.read(fd, 262144)
                except OSError:
                    break
                if b"GEND_ZX9" in buf:
                    break
        text = buf.decode("utf-8", "replace")
        if "GEND_ZX9" not in text:
            print("timeout waiting for GEND marker; got %d bytes" % len(buf))
            sys.exit(1)
        body = text.split("GBEGIN_ZX9", 1)[1].split("GEND_ZX9", 1)[0]
        lines = []
        for ln in body.splitlines():
            ln = ln.strip()
            if not ln:
                continue
            b = ln.encode()
            if len(b) % 4 == 0 and B64LINE.match(b):
                lines.append(b)
        data = base64.b64decode(b"".join(lines))
        open(args.out, "wb").write(data)
        local_md5 = hashlib.md5(data).hexdigest()
        print("got %d bytes md5=%s -> %s" % (len(data), local_md5, args.out))
        if remote_md5 and local_md5 != remote_md5:
            print("MD5 MISMATCH")
            sys.exit(2)
        print("MD5 OK")
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
