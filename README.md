# Vaaka

A focused, minimal macOS browser designed for productivity. Vaaka streamlines web browsing by letting you pin your most-used sites as vertical tabs - no address bar, no clutter, just the web.

## What is Vaaka?

Vaaka is a macOS browser built for focus and efficiency. It replaces traditional tab management with a **fixed, predefined site list** that you configure once in settings. Each whitelisted site gets exactly one vertical tab on the left sidebar, making it impossible to accumulate browser clutter.

### Perfect for:

- **Staying focused** on a curated set of sites
- **Eliminating context switching** between dozens of open tabs
- **Power users** who want full control over their browsing environment
- **Teams** that want to enforce a consistent, distraction-free workflow

## How It Works

1. **Configure Your Sites** - Add your preferred websites in Settings (e.g., Gmail, Slack, GitHub, documentation sites)
2. **Pin & Forget** - Your site list is locked; no accidental tabs, no tab sprawl
3. **Navigate with Keyboard** - Use Cmd+1 through Cmd+9 to jump between sites instantly
4. **Browse Normally** - Full WebKit support for JavaScript, CSS, and modern web standards
5. **Content Blocking** (Optional) - Block trackers and ads using built-in content rules

### Features

- **Vertical Tab Rail** - Clean left sidebar with site favicons
- **Keyboard Navigation** - Cmd+Number for quick switching, Ctrl+Tab for cycling
- **Session Persistence** - Window size and active tab are restored on launch
- **Favicon Fetching** - Automatic favicon download with fallback to monochrome icons
- **Content Blocking** - Optional ad/tracker blocking via EasyList integration
- **SSO Detection** - Alerts you when visiting OAuth/SAML login flows
- **User-Agent Spoofing** - Appears as Safari to avoid differential treatment
- **Do Not Track Support** - Optional DNT header for privacy-conscious browsing

## Limitations

### Sites That Won't Work

Some websites are **incompatible with Vaaka** due to security restrictions outside our control:

- **Slack** - Enforces restrictive CSP headers that block embedded web views
- **Microsoft Teams** - Similar embedding restrictions
- **Other enterprise SaaS** - Many corporate platforms block iframe/WebView access
- **Banking sites** - Often require specific user-agent strings or disable WebView access
- **Sites requiring specific browser features** - Some use APIs unavailable in embedded WebKit instances

### Known Constraints

- **No address bar** - By design. You can't navigate to arbitrary URLs; only your configured sites are accessible
- **Single-page view** - One site visible at a time (switch via Cmd+Number)
- **Whitelist-only** - All navigation is restricted to configured domains and their subdomains
- **macOS only** - Vaaka is built for macOS 14+; no Windows/Linux version
- **No extensions** - Browser extensions are not supported
- **No sync** - Site settings are local to your Mac; no cloud sync

### When to Use Something Else

If you need:

- Multi-site simultaneous viewing
- Arbitrary URL navigation
- Browser extensions
- Cross-platform sync
- Support for restricted enterprise sites

then a traditional browser like Safari or Chrome is a better fit.

## Installation

### From Release

Download the latest `.dmg` from [Releases](https://github.com/twistermc/Vaaka/releases) and drag `Vaaka.app` to your Applications folder.

### Building from Source

Requirements:

- macOS 14.0 or later
- Swift 5.9+

```bash
git clone <repo-url>
cd Vaaka
swift build -c release
```

The compiled app will be in `.build/release/Vaaka`.

## Usage

### Settings

Open **Vaaka - Settings** (or Cmd+,) to:

- Add/remove/edit sites
- Configure content blocking
- Adjust privacy settings

### Keyboard Shortcuts

| Shortcut       | Action           |
| -------------- | ---------------- |
| Cmd+1–9        | Jump to site 1–9 |
| Cmd+,          | Open Settings    |
| Cmd+Q          | Quit Vaaka       |
| Ctrl+Tab       | Next site        |
| Ctrl+Shift+Tab | Previous site    |

### Content Blocking

Enable "Block Trackers & Ads" in Settings to automatically block known ad networks and tracking pixels using EasyList rules.

### Privacy

- **DNT Header** - Enable "Send Do Not Track" to include the DNT header in requests (privacy signal)
- **User-Agent** - Vaaka masquerades as Safari to prevent differential content delivery

## Troubleshooting

### Site won't load

- Verify the site is in your Settings whitelist
- Check that the domain is correct (e.g., `github.com`, not `github`)
- Some sites may have embedding restrictions (see **Limitations**)

### Content blocking causing issues

- Disable "Block Trackers & Ads" if a site breaks
- Report problematic sites so we can refine the filter list

## System Requirements

- macOS 14.0 or later
- Apple Silicon (M1+) or Intel (Monterey+)

## Contributing

Vaaka is open source. To contribute:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## License

MIT License - See `LICENSE` file for details.

## FAQ

**Q: Can I add any website?**  
A: Yes, but some sites block WebView access for security reasons (see **Limitations**).

**Q: Is my browsing data private?**  
A: Yes. Vaaka stores all data locally on your Mac. We don't collect telemetry.

**Q: Can I use Vaaka alongside Safari?**  
A: Absolutely. Vaaka is meant to complement focused work; use Safari for general browsing.

**Q: Why are there only 9 keyboard shortcuts?**  
A: Vaaka is designed for power users with 5–10 regularly used sites. If you need more, consider a traditional browser.
