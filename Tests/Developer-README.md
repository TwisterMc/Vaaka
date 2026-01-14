# Developer README

## Building from Source

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
