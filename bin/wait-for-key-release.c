/*
 * wait-for-key-release — block until a named X11 key is physically released.
 *
 * Why: xmonad keybindings fire while the user is still holding the trigger
 * key (e.g. Super+V — Super is still down when the binding's command runs).
 * If that command then synthesises another keystroke via xdotool, the
 * X server's physical-modifier state still says "Super held" and the
 * receiving app sees Super+<synthetic-keystroke>. xdotool's --clearmodifiers
 * only clears its OWN synthetic event, not the physical Super-down emitted
 * upstream (e.g. by keyd).
 *
 * This program polls XQueryKeymap (a fast, in-X-server query) every 2ms
 * and returns as soon as the named key's bit is clear. Bounded by an
 * optional timeout to avoid hanging if the user really keeps the key held.
 *
 * Usage:
 *     wait-for-key-release [--timeout-ms N] [--poll-us N] <keysym-name>
 *
 * Examples:
 *     wait-for-key-release Super_L
 *     wait-for-key-release --timeout-ms 500 --poll-us 1000 Super_L
 *
 * Exit codes:
 *     0  the key was released (or never down) within the timeout
 *     2  the key is still held when the timeout expired
 *     3  X server unavailable
 *     4  unknown keysym name
 *     64 usage error
 *
 * Cold start: ~2ms on this box (single XOpenDisplay + XStringToKeysym +
 * loop of XQueryKeymap calls).
 */

#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void usage(FILE *out) {
    fputs("usage: wait-for-key-release [--timeout-ms N] [--poll-us N] <keysym-name>\n",
          out);
}

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(int argc, char **argv) {
    long timeout_ms = 1000;
    long poll_us    = 2000;

    static struct option opts[] = {
        {"timeout-ms", required_argument, 0, 't'},
        {"poll-us",    required_argument, 0, 'p'},
        {"help",       no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    int c;
    while ((c = getopt_long(argc, argv, "t:p:h", opts, NULL)) != -1) {
        switch (c) {
            case 't': timeout_ms = atol(optarg); break;
            case 'p': poll_us    = atol(optarg); break;
            case 'h': usage(stdout); return 0;
            default:  usage(stderr); return 64;
        }
    }
    if (optind >= argc) {
        usage(stderr);
        return 64;
    }
    const char *keysym_name = argv[optind];

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "wait-for-key-release: cannot open X display\n");
        return 3;
    }

    KeySym ks = XStringToKeysym(keysym_name);
    if (ks == NoSymbol) {
        fprintf(stderr, "wait-for-key-release: unknown keysym '%s'\n", keysym_name);
        XCloseDisplay(dpy);
        return 4;
    }
    KeyCode kc = XKeysymToKeycode(dpy, ks);
    if (kc == 0) {
        fprintf(stderr, "wait-for-key-release: keysym '%s' has no keycode\n",
                keysym_name);
        XCloseDisplay(dpy);
        return 4;
    }

    long long deadline = now_ms() + timeout_ms;
    char keymap[32];
    while (1) {
        XQueryKeymap(dpy, keymap);
        unsigned char b = (unsigned char)keymap[kc / 8];
        if (!(b & (1 << (kc % 8)))) {
            XCloseDisplay(dpy);
            return 0;
        }
        if (now_ms() >= deadline) {
            XCloseDisplay(dpy);
            return 2;
        }
        usleep((useconds_t)poll_us);
    }
}
