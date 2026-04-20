# Vaaka

Vaaka is a macOS browser built for focus and efficiency. It replaces traditional tab management with a fixed, predefined site list that you configure in settings. Each whitelisted site gets one tab on the left sidebar. Leaving the whitelisted sites opens your default browser. No address bar, no mess of tabs, just the sites you whitelist.

## Prototype Software - This is an early prototype. It's not perfect, but it's a solid proof of concept.

![Vaaka Screenshot](screenshot.png)

## Vaaka - "Vah-kah" (Finnish)

Means "scale" or "balance."

## Help Wanted

If you have experience with SwiftUI, WebKit, or macOS development and want to contribute, feel free to make pull requests.

If you want to help me get the app signed and notarized, I would greatly appreciate it.

## Background

The idea came from the Fluid app from back in the day, where I could whiltelist individual sites and have a browser that was specifically for those sites. Think SSB/progressive-web apps, but all in one window.

## How It Works

**Configure Your Sites** - Add your websites in Settings - That's it. Each site gets its own tab in the left sidebar.

### Features

- **Vertical Tabs** - Clean left sidebar with site favicons
- **Keyboard Navigation** - Cmd+Number for quick switching, Ctrl+Tab for cycling
- **Session Persistence** - Window size and active tab are restored on launch
- **Favicon Fetching** - Automatic favicon download with fallback to monochrome icons
- **Content Blocking** - Optional ad/tracker blocking via EasyList integration
- **User-Agent Spoofing** - Appears as Safari to avoid differential treatment
- **Do Not Track Support** - Optional - DNT header for privacy-conscious browsing
- **Local Data Storage** - All data is stored locally; no telemetry collected
- **Notifications** - Native macOS notifications for web alerts (I'm trying, but it's complicated.)
- **Unread Badge Counts** - Visual indicators for unread messages on supported sites (I'm trying, and we're getting closer.)
- **Tab Overview** - Preview all tabs in a grid view for quick navigation
- **Find Bar** - Search within the current page with a built-in find bar

## Installation

Download the latest release from [Releases](https://github.com/twistermc/Vaaka/releases), un-compress, and drag `Vaaka.app` to your Applications folder.

This app is currently **not code signed or notarized**. On first launch, macOS **will block it**.
To open it: go to **System Settings → Privacy & Security**, then click **Open Anyway** for Vaaka. If you download a new version, you'll have to follow the same steps again.

It's not signed because I haven't paid Apple the fee for a developer account at this time.

## Requirements:

- macOS 14.0 or later
- Apple Silicon or Intel

## Releasing a New Version

1. Update `Resources/Info.plist` — bump `CFBundleShortVersionString` to match the new version (e.g. `0.3`).
2. Commit the change: `git commit -am "Bump version to 0.3"`
3. Push a tag: `git tag v0.3 && git push --tags`

That's it. GitHub Actions will automatically:
- Build for both Apple Silicon and Intel
- Stamp the version from the tag into the app bundle
- Create a draft pre-release at [Releases](https://github.com/TwisterMc/Vaaka/releases) with both `.zip` files attached

Review the draft, edit the release notes, then publish it. The app's built-in update checker reads the tag from GitHub Releases, so users will be notified automatically on next launch.

> The workflow can also be triggered manually from the **Actions** tab if you need to build without tagging.

## Donate

If you find Vaaka useful and would like to support its development, consider [making a donation](https://ko-fi.com/twistermc).
Every bit helps and is greatly appreciated!
