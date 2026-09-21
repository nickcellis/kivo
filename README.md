# Kivo

A disk cleaner for macOS that shows its working. Kivo measures what is on
your Mac, explains why each thing is safe to remove or isn't, and puts
everything it takes somewhere you can get it back from.

![Kivo's dashboard](docs/screenshots/overview.png)

## What it does

**Clean** measures the folders a Mac rebuilds by itself: caches, logs, the
Trash, Xcode's derived data, npm and pnpm stores, simulator devices and
Docker's data. It sorts them into what is safe to remove, what comes back at the
cost of a download, and what Kivo will not touch. Downloads is measured and
left alone. Docker and the simulators are shown with the command that
reclaims them properly, because deleting those folders by hand confuses the
tools that own them.

![The Clean page](docs/screenshots/clean.png)

**Leftovers** finds support files whose app is gone, grouped by the vendor
that left them, so one app with forty widgets is one row rather than forty.

![The Leftovers page](docs/screenshots/leftovers.png)

**Duplicates** compares files by content, not by name: a size match, then a
64 KB head hash, then a full SHA-256, with hard links recognised as one file
rather than a copy of themselves.

![The Duplicates page](docs/screenshots/duplicates.png)

**Applications** lists what is installed with its version, size and last
use, and uninstalls one with everything it scattered around your Library.

![The Applications page](docs/screenshots/applications.png)

**Storage, Large Files and Disk Map** answer the other question: not what
can go, but where it all went. The map is a squarified treemap of every
folder, drawn to scale.

**Removed Items** is where everything Kivo takes goes first, with a button
to put any of it back where it came from.

## Safety

A cleaner is a program that deletes your files, so the rules are worth
stating plainly.

Nothing is deleted outright. Removals go to the Trash or to Kivo's own
holding area, and anything held can be restored to the exact path it came
from. Deleting something permanently is a separate decision you make later,
on a page built for making it.

Nothing is guessed at and then swept. The Leftovers list arrives with
nothing ticked, because there Kivo is inferring which app a folder belonged
to, and a wrong inference is Kivo's mistake rather than yours. Only folders
named in reverse DNS are even considered, so "Google" and "MobileSync" are
skipped: there is no honest way to decide who owns them. Apple's own
identifiers are never candidates at all.

An installed app protects its files, and that includes the helpers, widgets,
extensions and group containers named after it, apps that live in a folder
inside /Applications, and apps running from somewhere else entirely. Every
path is checked once more before anything moves, against a guard that
refuses anything outside the home folder's known locations.

All of this has tests, and the suite is mostly about what Kivo must not do.

## Install

Download the latest `Kivo.dmg` from
[Releases](https://github.com/nickcellis/kivo/releases), open it, and drag
Kivo to the Applications folder beside it.

Requires **macOS 14 Sonoma or later**, on Apple Silicon or Intel. The
binary is universal.

### macOS will block the first launch. Here is how to open it

Kivo is signed ad-hoc: macOS can confirm nobody has tampered with the app,
but it cannot say who made it, because that needs a Developer ID
certificate and a paid Apple membership this project doesn't have. So the
first double-click shows:

> **"Apple could not verify 'Kivo' is free of malware and may harm your
> Mac."**

That wording is alarming, and it isn't evidence of anything. macOS says
the same about every app from outside the App Store without a paid
certificate behind it. To open it:

1. Double-click Kivo and dismiss the warning. This is what puts the
   message into Settings, so it has to happen first.
2. Open **System Settings → Privacy & Security** and scroll down.
3. Beside *"Kivo was blocked to protect your Mac"*, click **Open Anyway**.
4. Authenticate, then click **Open** in the dialog that follows.

Once per Mac, and never again for that copy. (On macOS 14 you can instead
right-click the app and choose Open. Apple removed that shortcut in macOS
15, which is why the route above is longer than you may remember.)

**If you would rather not click past a malware warning**, which is a fair
instinct for an app that then asks for Full Disk Access, build it from
source instead. It takes one command, and an app you build yourself shows
no warning at all, because it was never downloaded. See
[Build it yourself](#build-it-yourself).

### Full Disk Access

Kivo then asks for **Full Disk Access**, which it needs to measure the
folders macOS protects, and which no app can grant itself: **System
Settings → Privacy & Security → Full Disk Access**, then add Kivo. Without
it Kivo still runs, and says which figures are incomplete.

## Build it yourself

Requires Xcode 16 or later and macOS 14 or later.

```bash
git clone https://github.com/nickcellis/kivo.git
cd kivo
xcodebuild -scheme Kivo -configuration Release -derivedDataPath build DEVELOPMENT_TEAM="" build
cp -R build/Build/Products/Release/Kivo.app /Applications/
```

Or open `kivo.xcodeproj` and press ⌘R.

`DEVELOPMENT_TEAM=""` clears the team stored in the project, which is not
yours; Xcode then signs the build ad-hoc, which needs no Apple account of
any kind. An app you built yourself carries no quarantine flag, so it
opens with no warning and no trip through System Settings, which is the
main reason this section exists. Set your own team in Xcode ▸ Signing &
Capabilities if you'd rather sign it properly. The App Sandbox is deliberately off: a sandboxed process cannot
read `~/Library/Caches`, `~/.Trash` or `/Applications`, so every figure Kivo
shows would be zero.

## Releasing

`Tools/release.sh` goes from a clean tree to a notarised, stapled disk
image in one command. It needs a **Developer ID Application** certificate
(an Apple Development certificate is a different thing and cannot be
notarised) and notary credentials stored once with `xcrun notarytool
store-credentials`. The script checks for both before it does anything and
says exactly what is missing.

The app is signed, notarised and stapled before the image is built around
it, so a copy dragged out of the image still validates on a Mac that is
offline the first time it runs; then the image itself is signed, notarised
and stapled, so the download passes Gatekeeper before anyone opens it.

`Tools/dmg.sh --adhoc` is the version with no certificate at all: it
builds the same image, but macOS cannot say who made it, so the first
launch is blocked. That is what the current release is.

## Tests

```bash
xcodebuild test -scheme Kivo -destination 'platform=macOS'
```

They run against temporary directories, never your real home folder. Every
piece of code that touches the file system takes the home folder as a
parameter, which is the fix for an early version that cleaned the author's
actual caches while under test.

## How it is put together

- `kivo/Core` holds everything that measures or moves a file, with no
  SwiftUI in it. `SystemScanner`, `SystemCleaner`, `OrphanFinder`, `DuplicateFinder`,
  `AppUninstaller`, `Quarantine`, `TreemapLayout`, and `ScanStore`, the one
  observable object the interface reads.
- `kivo/UI` has the window, the pages and the review sheets. `KivoTheme`
  holds every colour, size and font in the app.
- `kivoTests` is Swift Testing, mostly about the rules above.
- `Tools` holds the scripts: `render-icon.sh` draws the app icon from code,
  `shoot.sh` refreshes the screenshots in this README.

The screenshots are taken from invented data (`DemoData.swift`, Debug only),
not from anybody's real disk.

## License

See [LICENSE](LICENSE). Short version: use it, read it, change it. If you
fork it or hand it on, keep the notice and credit the project with a link.
It is not an OSI-approved open-source license.
