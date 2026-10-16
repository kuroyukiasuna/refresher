# Refresher

A small macOS menu bar app that reminds you to rest your eyes.

Every 20 minutes, Refresher gives you a heads-up and then gently blurs the screen for a
20-second break: long enough to look at something far away, short enough not to break your
flow. It gets out of the way when you're on a call, and it notices when you've already
stepped away.

## Features

- **Gentle breaks.** A blurred, full-screen break on every display with a countdown. Postpone
  it or skip it (Esc) whenever you need to.
- **A heads-up first.** A small notice appears 30 seconds before each break, with Start Now,
  Postpone and Skip. It never steals focus from what you're typing.
- **Quiet during calls.** Breaks pause automatically while you're in a meeting, whether it's
  in Zoom, Microsoft Teams, Slack, FaceTime, Webex, Discord, or a browser (Google Meet,
  Teams or Zoom on the web). You don't need any of these apps installed; Refresher works
  with whatever you use.
- **Knows when you're away.** Five minutes without keyboard or mouse input, locking the
  screen, or putting the Mac to sleep counts as a break, so the timer starts over.
- **Long breaks, if you want them.** Optionally make every few breaks a longer one to stand
  up and stretch.
- **Lives in the menu bar.** See how long until the next break, take one now, or pause
  reminders for 15 minutes, an hour, or until you resume.
- **Private.** No accounts, no network access, no permission prompts. Refresher never
  records or listens to anything.

## Requirements

- macOS 14 Sonoma or later
- Apple's Command Line Tools (or Xcode) to build it

## Install

1. If you don't have the Command Line Tools yet, install them:

   ```sh
   xcode-select --install
   ```

2. Clone the repository and install the app:

   ```sh
   git clone https://github.com/kuroyukiasuna/refresher.git
   cd refresher
   make install
   ```

   This builds Refresher, copies it to `/Applications` and opens it. Look for the eye icon in
   the menu bar.

3. The Settings window opens the first time. Turn on **Launch at login** if you'd like
   Refresher to start with your Mac.

To try it without installing, run `make run` instead. It builds and opens the app from the
`build` folder.

## Using Refresher

Click the eye icon in the menu bar to:

- see when the next break is
- **Take a Break Now** or **Restart Timer**
- **Pause Breaks** for a while, or until you resume
- choose **Don't Pause for This Meeting** when you'd like breaks to continue during a call
- open **Settings…** to change how often breaks happen, how long they last, the heads-up,
  sounds, and which calls should pause them

The icon shows what Refresher is doing:

| Icon | Meaning |
| --- | --- |
| Eye | Counting down to the next break |
| Leaf | On a break |
| Video camera | Paused for a meeting or call |
| Pause | Paused from the menu |
| Moon | Paused while you're away or the screen is locked |

## How call detection works

Refresher checks every couple of seconds which apps are using the microphone, playing
sound, or using the camera. That's the same information behind the orange and green dots in
the menu bar. It never sees or hears what those apps are doing.

- When a call app uses the microphone, you're in a meeting.
- Some apps release the microphone while you're muted, so a call app's audio keeps the
  meeting going after it has used the microphone (up to 2 hours).
- A meeting ends 20 seconds after the last sign of it, so a short glitch won't bring up a
  break mid-call.
- If a call starts during a break, the break steps aside and comes back 2 minutes after the
  call ends.

In Settings you can choose which apps count. Zoom, Teams and Slack only appear there if they
are installed. You can also pause for **any app using the camera** (on by default) or
**any app using the microphone** (off by default, since dictation and voice memos would
count too).

## Troubleshooting

**A call isn't being detected.** Open Settings and look at **Right now** under Smart pause
while you're in the call. For more detail, run this from the project folder:

```sh
make detect
```

It prints which apps are using the microphone, sound and camera every two seconds. If your
call app isn't recognized, turn on **Any app using the microphone**, or open an issue with
the app's name and the bundle ID shown by `make detect`.

**Launch at login stopped working after moving the app.** Turn **Launch at login** off and on
again in Settings. It remembers where the app was when you turned it on.

**I see two break screens.** Another break reminder (LookAway, for example) is also running.
Quit one of them.

## Uninstall

Quit Refresher from its menu, turn off **Launch at login** first if you enabled it, then:

```sh
rm -rf /Applications/Refresher.app
defaults delete dev.refresher.Refresher   # removes saved settings
```

## Development

```sh
make run        # build build/Refresher.app and open it
make install    # build, copy to /Applications and open it
make test       # unit tests for the scheduler and detection rules
make detect     # print what call detection sees every 2 seconds
make clean      # remove build output
```

Settings are stored in seconds, so you can try short timers without waiting 20 minutes:

```sh
defaults write dev.refresher.Refresher workInterval -float 30
defaults write dev.refresher.Refresher shortBreakDuration -float 8
defaults delete dev.refresher.Refresher     # back to defaults
```

Quit and reopen the app after changing them.

### Project layout

- `Sources/RefresherCore`: the break scheduler, call-detection rules and formatting. Plain
  Swift with no AppKit, covered by `Tests/RefresherCoreTests`.
- `Sources/Refresher`: the app itself: Core Audio and camera polling, the menu bar item, the
  break screen, the heads-up panel and Settings.
- `scripts/build-app.sh` builds the `.app` bundle; `scripts/make-icon.swift` draws the icon.

The list of recognized call apps and browsers is in
`Sources/RefresherCore/MeetingDetector.swift`.

### Notes

- The app is ad-hoc signed for local use, not notarized, so it's meant to be built from
  source on the Mac that runs it.
- Calls often run in helper processes (Slack Helper, Teams' WebKit services, Chrome's audio
  service). To match them to their app, Refresher uses one private macOS function,
  `responsibility_get_pid_responsible_for_pid`, which Chromium and Firefox also use. It's
  looked up at runtime and falls back to executable paths if it's ever missing. That's fine
  outside the Mac App Store, which wouldn't allow it.
- With the macOS 27 SDK and only the Command Line Tools, SwiftUI's `@State` is a macro whose
  plugin ships only with Xcode, so the code avoids `@State`.
