"""Share clipboard data through an SSH Unix socket."""

import argparse
import hashlib
import os
import re
import shutil
import socket
import socketserver
import stat
import subprocess
import sys
from pathlib import Path

MAX_BYTES = 64 * 1024 * 1024
TIMEOUT = 10
IMAGE_TYPES = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/webp": ".webp",
    "image/gif": ".gif",
}


def session_socket(session, prepare=False):
    directory = Path("/tmp") / f"dotfiles-clipboard-{os.getuid()}"
    if prepare:
        directory.mkdir(mode=0o700, exist_ok=True)
    if directory.exists() or directory.is_symlink():
        info = directory.lstat()
        if (
            not stat.S_ISDIR(info.st_mode)
            or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o700
        ):
            raise RuntimeError(f"unsafe clipboard directory: {directory}")
    name = hashlib.sha256(session.encode()).hexdigest()[:24]
    path = directory / f"{name}.sock"
    if prepare and (path.exists() or path.is_symlink()):
        info = path.lstat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
            raise RuntimeError(f"unsafe clipboard socket: {path}")
        path.unlink()
    return path


def remote_socket():
    session = os.environ.get("ZMX_SESSION")
    if not session:
        return None
    path = session_socket(session)
    if os.environ.get("SSH_CONNECTION") or os.environ.get("SSH_TTY") or path.exists():
        return path
    return None


def native_binary(name):
    return shutil.which(name, path=os.environ.get("CLIPBOARD_NATIVE_PATH"))


def native_command(copy, mime=None):
    if os.environ.get("WAYLAND_DISPLAY") and native_binary("wl-copy" if copy else "wl-paste"):
        command = [native_binary("wl-copy")] if copy else [native_binary("wl-paste"), "--no-newline"]
        return command + (["--type", mime] if mime else [])
    if os.environ.get("DISPLAY") and native_binary("xclip"):
        command = [native_binary("xclip"), "-selection", "clipboard", "-in" if copy else "-out"]
        return command + (["-target", mime] if mime else [])
    if mime:
        raise RuntimeError("image clipboard requires X11 or Wayland")
    if native_binary("pbcopy" if copy else "pbpaste"):
        return [native_binary("pbcopy" if copy else "pbpaste")]
    if copy and native_binary("clip.exe"):
        return [native_binary("clip.exe")]
    if not copy and native_binary("powershell.exe"):
        return [native_binary("powershell.exe"), "-NoProfile", "-Command", "Get-Clipboard -Raw"]
    raise RuntimeError("no local clipboard provider is available")


def native_clipboard(copy, data=b"", mime=None):
    command = native_command(copy, mime)
    result = subprocess.run(
        command,
        input=data if copy else None,
        stdin=None if copy else subprocess.DEVNULL,
        stdout=subprocess.DEVNULL if copy else subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        timeout=TIMEOUT,
        check=True,
    )
    if result.stdout is not None and len(result.stdout) > MAX_BYTES:
        raise RuntimeError("clipboard data exceeds 64 MiB")
    return b"" if copy else result.stdout


def image_type(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    raise RuntimeError("clipboard does not contain a supported image")


def native_image():
    for mime in IMAGE_TYPES:
        try:
            data = native_clipboard(False, mime=mime)
            if image_type(data) == mime:
                return mime.encode() + b"\0" + data
        except (OSError, RuntimeError, subprocess.SubprocessError):
            continue
    raise RuntimeError("clipboard does not contain a supported image")


def clipboard_image():
    path = remote_socket()
    return request_operation(path, b"I") if path else native_image()


def tui_socket(session):
    return session_socket(session).with_suffix(".tui.sock")


def route_socket(session):
    return session_socket(session).with_suffix(".forward")


def forward_route(session, target=None):
    session_socket(session).parent.mkdir(mode=0o700, exist_ok=True)
    route = route_socket(session)
    if target is None:
        return route
    temporary = route.with_suffix(f".tmp-{os.getpid()}")
    try:
        temporary.symlink_to(target)
        temporary.replace(route)
    finally:
        temporary.unlink(missing_ok=True)
    return route


def paste_image_window(window):
    result = subprocess.run(
        ["xprop", "-id", str(window), "_ZMX_SESSION"],
        capture_output=True, text=True, check=True, timeout=2,
    )
    match = re.search(r'= "(.*)"', result.stdout)
    session = match[1] if match and match[1] else f"window:{window}"
    endpoint = route_socket(session)
    if not endpoint.is_symlink():
        endpoint = tui_socket(session)
    if not endpoint.exists():
        return
    try:
        image = native_image()
    except RuntimeError:
        return
    request_operation(endpoint, b"I", image)


def receive(stream):
    chunks = []
    size = 0
    while True:
        chunk = stream.recv(min(65536, MAX_BYTES + 1 - size))
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)
        size += len(chunk)
        if size > MAX_BYTES:
            raise RuntimeError("clipboard data exceeds 64 MiB")


def request(path, copy, data):
    return request_operation(path, b"C" if copy else b"P", data)


def request_operation(path, operation, data=b""):
    with socket.socket(socket.AF_UNIX) as stream:
        stream.settimeout(TIMEOUT + 2)
        try:
            stream.connect(str(path))
        except OSError as error:
            raise RuntimeError("local clipboard is disconnected; reconnect with jc") from error
        stream.sendall(operation + data)
        stream.shutdown(socket.SHUT_WR)
        response = receive(stream)
    if not response:
        raise RuntimeError("clipboard bridge closed without a response")
    if response[:1] != b"\0":
        raise RuntimeError(response[1:].decode(errors="replace"))
    return response[1:]


class ClipboardRequest(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(TIMEOUT)
        try:
            operation = self.request.recv(1)
            if operation not in (b"C", b"P", b"I"):
                raise RuntimeError("invalid clipboard operation")
            data = receive(self.request)
            if operation in (b"P", b"I") and data:
                raise RuntimeError("paste requests cannot contain data")
            result = native_image() if operation == b"I" else native_clipboard(operation == b"C", data)
            self.request.sendall(b"\0" + result)
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            try:
                self.request.sendall(b"\1" + str(error).encode())
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    copy = commands.add_parser("copy", help="copy standard input or files")
    copy.add_argument("files", nargs="*")
    paste = commands.add_parser("paste", help="write clipboard contents to standard output")
    paste.add_argument("--image", action="store_true")
    prepare = commands.add_parser("prepare", help="prepare a private remote session socket")
    prepare.add_argument("session")
    serve = commands.add_parser("serve", help="serve the native clipboard on a Unix socket")
    serve.add_argument("socket")
    commands.add_parser("active", help="check whether this shell uses a forwarded clipboard")
    route = commands.add_parser("forward-route", help="publish a forwarded TUI socket")
    route.add_argument("session")
    route.add_argument("target", nargs="?")
    window = commands.add_parser("paste-image-window", help="paste an image into the window's TUI")
    window.add_argument("window", type=int)
    tui = commands.add_parser("tui", help="run a TUI with clipboard integration")
    tui.add_argument("argv", nargs=argparse.REMAINDER)
    proxy = commands.add_parser("provider", help="adapt a TUI clipboard command")
    proxy.add_argument("provider")
    proxy.add_argument("args", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if args.command == "prepare":
        print(session_socket(args.session, prepare=True))
        return 0
    if args.command == "forward-route":
        print(forward_route(args.session, args.target))
        return 0
    if args.command == "paste-image-window":
        paste_image_window(args.window)
        return 0
    if args.command == "tui":
        from clipboard_tui import run_tui
        return run_tui(args.argv[1:] if args.argv[:1] == ["--"] else args.argv)
    if args.command == "provider":
        from clipboard_tui import provider
        return provider(args.provider, args.args)
    if args.command == "serve":
        os.umask(0o077)
        with socketserver.UnixStreamServer(args.socket, ClipboardRequest) as server:
            try:
                server.serve_forever()
            finally:
                Path(args.socket).unlink(missing_ok=True)
        return 0
    path = remote_socket()
    if args.command == "active":
        return 0 if path else 1
    if args.command == "paste" and args.image:
        sys.stdout.buffer.write(clipboard_image().split(b"\0", 1)[1])
        return 0
    copying = args.command == "copy"
    data = b""
    if copying:
        if args.files:
            data = b"".join(
                sys.stdin.buffer.read() if name == "-" else Path(name).read_bytes()
                for name in args.files
            )
        else:
            data = sys.stdin.buffer.read()
        if len(data) > MAX_BYTES:
            raise RuntimeError("clipboard data exceeds 64 MiB")
    result = request(path, copying, data) if path else native_clipboard(copying, data)
    if not copying:
        sys.stdout.buffer.write(result)
    return 0


