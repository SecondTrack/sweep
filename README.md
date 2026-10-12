# Sweep

**See what's eating your iPod's 256 MB of RAM – and close it with one tap.**

iOS 6 keeps apps in the background until memory runs out, and on an iPod touch 4 that happens fast. Tasks shows free memory and every running app, and closes one or all of them.

## What it can do

- Free memory with a bar, measured like the system does it (free + inactive pages).
- All running apps, sorted by name (SpringBoard is left out, so nothing important gets killed).
- Close single apps or all at once, and see how many MB that freed.

## Runs on

iOS 6.1.6 · jailbroken iPod touch 4

## Install

Easiest via the **[Reboot App Store](https://github.com/SecondTrack/reboot)** right on the iPod. By hand: `.deb` from the [latest release](https://github.com/SecondTrack/tasks/releases/latest), `dpkg -i`, then `uicache`.

Build it yourself with [Theos](https://theos.dev): `make package` (iOS 6.0+, armv7).

## License

GPL-3.0 – see [LICENSE](LICENSE).
Not affiliated with Apple. iPod is a trademark of Apple Inc.
