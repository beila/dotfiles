"""Adapt terminal applications to the local or forwarded clipboard."""

import errno
import fcntl
import os
import pty
import select
import shlex
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import termios
import time
import tty
from pathlib import Path

from clipboard_bridge import (
    IMAGE_TYPES,
    MAX_BYTES,
    TIMEOUT,
    clipboard_image,
    image_type,
    native_clipboard,
    receive,
    remote_socket,
    request,
    tui_socket,
)

BRACKET_START = b"\x1b[200~"
BRACKET_END = b"\x1b[201~"


def write_all(fd, data):
    while data:
        data = data[os.write(fd, data):]


class Input:
    def __init__(self, paste, alt_v=False):
        self.paste = paste
        self.pending = b""
        self.bracketed = False
        self.shortcuts = [b"\x16", b"\x1b[118;5u", b"\x1b[118;6u", b"\x1b[86;6u"]
        if alt_v:
            self.shortcuts.extend([b"\x1bv", b"\x1b[118;3u"])

    def feed(self, data, flush=False):
        data = self.pending + data
        self.pending = b""
        output = bytearray()
        index = 0
        while index < len(data):
            marker = BRACKET_END if self.bracketed else BRACKET_START
            tail = data[index:index + 16]
            tokens = [marker] if self.bracketed else [marker, *self.shortcuts]
            if not flush and any(token.startswith(tail) and token != tail for token in tokens):
                self.pending = tail
                break
            if tail.startswith(marker):
                self.bracketed = not self.bracketed
                output.extend(marker)
                index += len(marker)
            elif not self.bracketed and (shortcut := next(
                (token for token in self.shortcuts if tail.startswith(token)), None
            )):
                output.extend(self.paste())
                index += len(shortcut)
            else:
                output.append(data[index])
                index += 1
        return bytes(output)


def store_image(packet, directory):
    mime, data = packet.split(b"\0", 1)
    mime = mime.decode("ascii")
    if mime not in IMAGE_TYPES or image_type(data) != mime:
        raise RuntimeError("invalid clipboard image")
    fd, name = tempfile.mkstemp(prefix="paste-", suffix=IMAGE_TYPES[mime], dir=directory)
    with os.fdopen(fd, "wb") as image:
        image.write(data)
    return BRACKET_START + shlex.quote(name).encode() + BRACKET_END


def paste(directory):
    try:
        return store_image(clipboard_image(), directory)
    except (OSError, RuntimeError, subprocess.SubprocessError):
        path = remote_socket()
        data = request(path, False, b"") if path else native_clipboard(False)
        return BRACKET_START + data + BRACKET_END


def run_tui(argv):
    if not argv:
        raise RuntimeError("tui requires a command")
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        os.execvp(argv[0], argv)
    session = os.environ.get("ZMX_SESSION") or f"window:{os.environ.get('WINDOWID', os.getpid())}"
    endpoint = tui_socket(session)
    endpoint.parent.mkdir(mode=0o700, exist_ok=True)
    if endpoint.is_symlink():
        raise RuntimeError("unsafe TUI socket")
    if endpoint.exists():
        probe = socket.socket(socket.AF_UNIX)
        try:
            probe.connect(str(endpoint))
        except ConnectionRefusedError:
            info = endpoint.lstat()
            if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
                raise RuntimeError("unsafe TUI socket")
            endpoint.unlink()
        else:
            raise RuntimeError("a clipboard TUI is already running in this session")
        finally:
            probe.close()
    images = Path(tempfile.mkdtemp(prefix="images-", dir=endpoint.parent))
    listener = socket.socket(socket.AF_UNIX)
    old_mask = os.umask(0o077)
    try:
        listener.bind(str(endpoint))
    finally:
        os.umask(old_mask)
    listener.listen(4)
    env = dict(os.environ)
    env["CLIPBOARD_NATIVE_PATH"] = env.get("CLIPBOARD_NATIVE_PATH", env["PATH"])
    env["PATH"] = str(Path(__file__).parent / "clipboard-tools") + os.pathsep + env["PATH"]
    child, master = pty.fork()
    if child == 0:
        listener.close()
        os.execvpe(argv[0], argv, env)
    previous = termios.tcgetattr(0)
    old_handlers = {}
    child_status = None

    def resize(*_):
        size = fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8)
        fcntl.ioctl(master, termios.TIOCSWINSZ, size)

    def terminate(signum, _frame):
        os.kill(child, signum)

    parser = Input(lambda: paste(images), alt_v=Path(argv[0]).name == "claude")
    try:
        resize()
        for signum, handler in (
            (signal.SIGWINCH, resize), (signal.SIGTERM, terminate),
            (signal.SIGHUP, terminate), (signal.SIGINT, terminate),
        ):
            old_handlers[signum] = signal.signal(signum, handler)
        tty.setraw(0)
        while True:
            ready, _, _ = select.select([0, master, listener], [], [], 0.03)
            if master in ready:
                try:
                    data = os.read(master, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not data:
                    break
                write_all(1, data)
            if 0 in ready:
                data = os.read(0, 65536)
                if not data:
                    break
                try:
                    write_all(master, parser.feed(data))
                except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                    write_all(2, f"\r\nclipboard: {error}\r\n".encode())
            elif parser.pending:
                write_all(master, parser.feed(b"", flush=True))
            if listener in ready:
                with listener.accept()[0] as connection:
                    connection.settimeout(TIMEOUT)
                    try:
                        operation = connection.recv(1)
                        packet = receive(connection)
                        if operation != b"I":
                            raise RuntimeError("invalid TUI clipboard operation")
                        write_all(master, store_image(packet, images))
                        connection.sendall(b"\0")
                    except (OSError, RuntimeError, ValueError) as error:
                        try:
                            connection.sendall(b"\1" + str(error).encode())
                        except OSError:
                            pass
            if child_status is None:
                reaped, status = os.waitpid(child, os.WNOHANG)
                if reaped:
                    child_status = status
    finally:
        termios.tcsetattr(0, termios.TCSADRAIN, previous)
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)
        listener.close()
        endpoint.unlink(missing_ok=True)
        os.close(master)
        if child_status is None:
            try:
                os.kill(child, signal.SIGHUP)
            except ProcessLookupError:
                pass
            _, child_status = os.waitpid(child, 0)
        # Keep attachments available to the application's saved conversation.
        for old in endpoint.parent.glob("images-*"):
            if old.is_dir() and not old.is_symlink() and time.time() - old.stat().st_mtime > 7 * 86400:
                for image in old.iterdir():
                    if image.is_file() and not image.is_symlink():
                        image.unlink()
                try:
                    old.rmdir()
                except OSError:
                    pass
        if not any(images.iterdir()):
            images.rmdir()
    result = os.waitstatus_to_exitcode(child_status)
    return 128 - result if result < 0 else result


def provider(name, args):
    copying = name == "wl-copy" or (name == "xclip" and not any(a in ("-o", "-out") for a in args))
    mime = None
    for index, arg in enumerate(args):
        if arg in ("-t", "-target", "--type") and index + 1 < len(args):
            mime = args[index + 1]
    if mime == "TARGETS" or "--list-types" in args:
        types = ["text/plain", "UTF8_STRING"]
        try:
            types.append(clipboard_image().split(b"\0", 1)[0].decode())
        except (OSError, RuntimeError, subprocess.SubprocessError):
            pass
        print("\n".join(types))
        return 0
    if mime in IMAGE_TYPES:
        if copying:
            raise RuntimeError("image writes through a TUI provider are unsupported")
        packet = clipboard_image()
        actual, data = packet.split(b"\0", 1)
        if actual.decode() != mime:
            raise RuntimeError("requested clipboard image type is unavailable")
    else:
        data = sys.stdin.buffer.read(MAX_BYTES + 1) if copying else b""
        if len(data) > MAX_BYTES:
            raise RuntimeError("clipboard data exceeds 64 MiB")
        path = remote_socket()
        data = request(path, copying, data) if path else native_clipboard(copying, data)
    if not copying:
        sys.stdout.buffer.write(data)
    return 0
