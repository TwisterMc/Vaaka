# Vaaka

Vaaka is a macOS browser built for focus and efficiency. It replaces traditional tab management with a **fixed, predefined site list** that you configure in settings. Each whitelisted site gets one tab on the left sidebar. Leaving the whitelisted sites opens your default browser. No address bar, no mess of tabs, just the sites you whitelist.

## Vaaka - "Vah-kah" (Finnish)

Means "scale" or "balance."

### Background

The idea came from the Fluid app from back in the day, where I could whiltelist individual sites and have a browser that was specifically for those sites. Think SSB/progressive-web apps, but all in one window.

### Perfect for:

- **Staying focused** on a curated set of sites
- **Eliminating context switching** between dozens of open tabs
- **Power users** who want full control over their browsing environment
- **Teams** that want to enforce a consistent, distraction-free workflow

## How It Works

**Configure Your Sites** - Add your preferred websites in Settings (e.g., Gmail, Slack, GitHub, documentation sites) - That's it.

### Features

- **Vertical Tabs** - Clean left sidebar with site favicons
- **Keyboard Navigation** - Cmd+Number for quick switching, Ctrl+Tab for cycling
- **Session Persistence** - Window size and active tab are restored on launch
- **Favicon Fetching** - Automatic favicon download with fallback to monochrome icons
- **Content Blocking** - Optional ad/tracker blocking via EasyList integration
- **SSO Detection** - Alerts you when visiting OAuth/SAML login flows
- **User-Agent Spoofing** - Appears as Safari to avoid differential treatment
- **Do Not Track Support** - Optional - DNT header for privacy-conscious browsing
- **Local Data Storage** - All data is stored locally; no telemetry collected
- **Notifications** - Native macOS notifications for web alerts (Disabled until signed)
- **Unread Badge Counts** - Visual indicators for unread messages on supported sites
- **Tab Overview** - Hover over tabs to see a snapshot preview of the site

## Installation

### From Release

Download the latest release from [Releases](https://github.com/twistermc/Vaaka/releases), un-compress, and drag `Vaaka.app` to your Applications folder.

This app is self-signed and notarized by Apple. The first time you open it, you will need to right-click the app and select "Open" to bypass Gatekeeper or approve it in System Preferences > Security & Privacy.

It's not signed because I don't want to pay Apple the fee for a developer account at this time.

## Requirements:

- macOS 14.0 or later
- Apple Silicon (M1+) or Intel

## FAQ

**Q: Can I add any website?**  
A: Yes, but some sites block WebView access for security reasons (see **Limitations**).

**Q: Is my browsing data private?**  
A: Yes. Vaaka stores all data locally on your Mac. We don't collect telemetry.

**Q: Can I use Vaaka alongside Safari?**  
A: Absolutely. Vaaka is meant to complement focused work; use Safari for general browsing.

**Q: Why are there only 9 keyboard shortcuts?**  
A: Vaaka is designed for power users with 5–10 regularly used sites. If you need more, consider a traditional browser.
