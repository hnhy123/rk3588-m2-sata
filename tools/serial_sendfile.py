#!/usr/bin/env python3
"""Send a local file to the serial console target as base64, with md5 verify.

Usage: serial_sendfile.py --port /dev/ttyUSB0 --baud 1500000 --file x.tgz --remote /tmp/x.tgz.b64
"""
import argparse
import base64
import hashlib
import os
import select
import sys
import termios
import time


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
    if isinstance(needle, str):
        needle = needle.encode()
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
    p.add_argument("--file", required=True)
    p.add_argument("--remote", required=True)
    p.add_argument("--user", default="root")
    p.add_argument("--password", default=os.environ.get("SERIAL_PASSWORD", ""))
    p.add_argument("--chunk", type=int, default=2048)
    p.add_argument("--delay", type=float, default=0.02)
    args = p.parse_args()

    raw = open(args.file, "rb").read()
    b64 = base64.b64encode(raw)
    lines = [b64[i:i + 76] for i in range(0, len(b64), 76)]
    payload = b"\n".join(lines) + b"\n"
    size = len(raw)
    host_md5 = hashlib.md5(raw).hexdigest()
    print("file=%d bytes b64=%d bytes md5=%s" % (size, len(payload), host_md5))

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
        drain(fd, 0.5)

        os.write(fd, ("rm -f %s; echo SENDREADY\r" % args.remote).encode())
        ok, out = wait_for(fd, "SENDREADY", 8)
        if not ok:
            print("no SENDREADY; last output:")
            print(out.decode("utf-8", "replace"))
            sys.exit(1)

        os.write(fd, ("cat > %s\r" % args.remote).encode())
        time.sleep(0.4)
        drain(fd, 0.3)

        t0 = time.time()
        for i in range(0, len(payload), args.chunk):
            os.write(fd, payload[i:i + args.chunk])
            time.sleep(args.delay)
            if (i // args.chunk) % 32 == 0:
                drain(fd, 0.01)
        os.write(fd, b"\x04")
        time.sleep(0.5)
        drain(fd, 0.5)
        print("sent in %.1fs" % (time.time() - t0))

        os.write(fd, ("ls -l %s; wc -c %s\r" % (args.remote, args.remote)).encode())
        out = drain(fd, 3.0, quiet_stop=1.0)
        print(out.decode("utf-8", "replace"))

        os.write(fd, ("base64 -d %s > %s && md5sum %s && echo DECODED_OK\r"
                      % (args.remote, args.remote + ".bin", args.remote + ".bin")).encode())
        out = drain(fd, 25.0, quiet_stop=2.0)
        txt = out.decode("utf-8", "replace")
        print(txt)
        if host_md5 in txt:
            print("MD5 MATCH OK")
        else:
            print("MD5 MISMATCH (expected %s)" % host_md5)
            sys.exit(2)
    finally:
        os.close(fd)


if __name__ == "__main__":
    main()
