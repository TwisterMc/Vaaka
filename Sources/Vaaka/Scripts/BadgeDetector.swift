import Foundation

struct BadgeDetector {
    static let script = """
    (function() {
        // Robust badge detector with queued delivery and multiple heuristics.
        const isSlack = window.location.hostname.includes('slack.com');
        const isGmail = window.location.hostname.includes('mail.google.com');

        let lastReportedCount = -1;
        let stableCycles = 0;
        let pollInterval = 2000; // start relatively responsive, back off when stable
        let retryQueue = [];
        let maxRetryMs = 10_000; // keep retrying for a short period if native handler isn't ready

        function parseTitleCount(title) {
            if (!title) return 0;
            const patterns = [
                /\\((\\d{1,5})\\)/,
                /\\[(\\d{1,5})\\]/,
                /(?:^|\\W)(\\d{1,4})\\s*(?:unread|new|messages?)\\b/i,
                /(?:^|\\W)(\\d{1,4})(?=\\s*[\\|\\u2022\\u00B7•·])/i,
                /(?:[\\|\\u2022\\u00B7•·\\-—]\\s*)(\\d{1,4})/i,
                // Avoid matching numbers that are *before* a separator (common in dates/labels).
                // Instead match numbers *after* pipe/bullet (e.g. "Site | 5" or "Site • 5").
                /(?:[\\|\\u2022\\u00B7•·]\\s*)(\\d{1,4})/,
                /[\\u2022\\u00B7•·]\\s*(\\d{1,4})/,
                /(?:^|\\W)(\\d{1,4})\\b/
            ];
            for (const re of patterns) {
                const m = title.match(re);
                if (m && m[1]) {
                    const v = parseInt(m[1], 10);
                    if (!Number.isNaN(v) && v >= 0 && v < 10000) return v;
                }
            }
            return 0;
        }

        function findDomBadge() {
            // site-specific fallbacks + a few generic tries
            try {
                // Gmail: inbox nav badge
                if (isGmail) {
                    const inboxNav = document.querySelector('[role=\"navigation\"] [title*=\"Inbox\"]');
                    if (inboxNav) {
                        const m = inboxNav.textContent.match(/\\d+/);
                        if (m) return parseInt(m[0], 10);
                    }
                }

                // Slack: common selectors
                if (isSlack) {
                    const badge = document.querySelector('.p-ia__sidebar_header__count, [data-qa=\"unreads_count\"], .p-channel_sidebar__badge');
                    if (badge) {
                        const m = badge.textContent.match(/\\d+/);
                        if (m) return parseInt(m[0], 10);
                    }
                }

                // Generic: look for explicit badge-like elements only.  Avoid scanning arbitrary page text to reduce false-positives.
                const candidates = Array.from(document.querySelectorAll('[data-unread],[data-count],[aria-label],[title],span,div'));
                for (const el of candidates) {
                    // Prefer explicit attributes first
                    const attrNum = el.getAttribute('data-unread') || el.getAttribute('data-count');
                    if (attrNum && /^\\d{1,3}$/.test(attrNum.trim())) return parseInt(attrNum.trim(), 10);

                    const label = (el.getAttribute('aria-label') || el.getAttribute('title') || '').toLowerCase();
                    if (label) {
                        const m = label.match(/(\\d{1,3})/);
                        if (m && /unread|inbox|new|messages?|notifications?/.test(label)) return parseInt(m[1], 10);
                    }

                    // As a last resort accept short numeric-only text nodes that are visually a badge (class/name hints)
                    const txt = (el.textContent || '').trim();
                    if (/^\\d{1,3}$/.test(txt)) {
                        const cls = (el.className || '').toLowerCase();
                        const parentCls = (el.parentElement && el.parentElement.className) ? el.parentElement.className.toLowerCase() : '';
                        if (/(badge|count|unread|notification|indicator)/.test(cls) || /(badge|count|unread|notification|indicator)/.test(parentCls)) {
                            return parseInt(txt, 10);
                        }
                    }
                }
            } catch (e) {
                // Defensive: DOM queries can throw in some pages
                console.debug('[Vaaka] DOM badge detection error', e);
            }
            return 0;
        }

        function postCount(count, source) {
            const payload = { count: count, source: source || 'unknown', ts: Date.now() };
            // If native injected a handshake at documentStart, prefer that fast-path (avoids queuing)
            try {
                if (window.__vaaka_native_ready) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.badgeUpdate) {
                        // flush any queued messages first
                        if (retryQueue.length) {
                            for (const q of retryQueue) {
                                window.webkit.messageHandlers.badgeUpdate.postMessage(q);
                            }
                            retryQueue = [];
                        }
                        window.webkit.messageHandlers.badgeUpdate.postMessage(payload);
                        return true;
                    }
                }
            } catch (e) {
                // fall through to existing detection (will queue)
            }

            // Fast-path when handshake isn't available yet: try the handler directly
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.badgeUpdate) {
                    // flush any queued messages first
                    if (retryQueue.length) {
                        for (const q of retryQueue) {
                            window.webkit.messageHandlers.badgeUpdate.postMessage(q);
                        }
                        retryQueue = [];
                    }
                    window.webkit.messageHandlers.badgeUpdate.postMessage(payload);
                    return true;
                }
            } catch (e) {
                // fall through to queue
            }

            // If native handler missing, queue the latest value and retry for a short period
            const entry = Object.assign({ queuedAt: Date.now() }, payload);
            retryQueue = [entry]; // keep only the latest to avoid flooding
            scheduleRetryIfNeeded();
            return false;
        }

        let retryTimer = null;
        function scheduleRetryIfNeeded() {
            if (retryTimer) return;
            retryTimer = setInterval(() => {
                const now = Date.now();
                retryQueue = retryQueue.filter(q => now - q.queuedAt < maxRetryMs);
                if (retryQueue.length === 0) {
                    clearInterval(retryTimer);
                    retryTimer = null;
                    return;
                }
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.badgeUpdate) {
                        for (const q of retryQueue) window.webkit.messageHandlers.badgeUpdate.postMessage(q);
                        retryQueue = [];
                        clearInterval(retryTimer);
                        retryTimer = null;
                    }
                } catch (e) {
                    // ignore and retry until expired
                }
            }, 300);
        }

        function detectBadge() {
            let count = 0;

            // 1) Title-based (most reliable)
            const title = document.title || '';
            count = parseTitleCount(title);

            // 2) DOM-based fallbacks only if title yields 0
            if (count === 0) count = findDomBadge();

            // Coerce
            if (!Number.isInteger(count) || count < 0) count = 0;

            // Only report if changed
            if (count !== lastReportedCount) {
                lastReportedCount = count;
                stableCycles = 0;
                postCount(count, 'delta');
            } else {
                stableCycles++;
                // back off polling when stable
                if (stableCycles > 6) pollInterval = 5000;
            }
        }

        // Initial detection + more aggressive observation for dynamic pages
        detectBadge();

        // Title observer (fast path)
        const titleEl = document.querySelector('title');
        if (titleEl) {
            new MutationObserver(() => detectBadge()).observe(titleEl, { childList: true, characterData: true, subtree: true });
        }

        // Observe body for DOM changes that might affect badges
        try {
            const body = document.body;
            if (body) {
                const mo = new MutationObserver((mutations) => {
                    // coarse-grained: run detection on relevant changes
                    for (const m of mutations) {
                        if (m.type === 'childList' || m.type === 'characterData' || m.type === 'attributes') {
                            detectBadge();
                            break;
                        }
                    }
                });
                mo.observe(body, { childList: true, subtree: true, characterData: true, attributes: true });
            }
        } catch (e) {
            // ignore
        }

        // Poll with adaptive interval
        let pollTimer = setInterval(() => {
            detectBadge();
            // adjust interval if needed
            clearInterval(pollTimer);
            pollTimer = setInterval(detectBadge, pollInterval);
        }, pollInterval);

        // Expose a small handshake so pages/scripts can know we're present
        try {
            window.__vaakaBadgeDetector = { version: 1, lastCount: () => lastReportedCount };
        } catch (e) {}

        console.log('[Vaaka] Badge detector active');
    })();
    """

    // Swift-side helper for unit testing title parsing logic
    static func parseTitleCount(_ title: String) -> Int {
        let patterns = [
            "\\((\\d{1,5})\\)",
            "\\(\\s*(?:unread|new|messages?)\\s*(\\d{1,4})\\s*\\)",
            "(?:\\b(?:unread|new|messages?)\\b\\s*(\\d{1,4}))",
            "\\[(\\d{1,5})\\]",
            "(?:^|\\W)(\\d{1,4})\\s*(?:unread|new|messages?)\\b",
                "(?:^|\\W)(\\d{1,4})\\s*(?:unread|new|messages?)\\b",
                "(?:^|\\W)(\\d{1,4})(?=\\s*[\\|\\u2022\\u00B7•·])",
                "(?:[\\|\\u2022\\u00B7•·\\-—]\\s*)(\\d{1,4})",
                // Match numbers that appear AFTER a pipe or bullet (common badge formats: "Site | 5" or "Site • 5")
                "(?:[\\|\\u2022\\u00B7•·]\\s*)(\\d{1,4})",
                "[\\u2022\\u00B7•·]\\s*(\\d{1,4})"
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let ns = title as NSString
                let range = NSRange(location: 0, length: ns.length)
                if let m = regex.firstMatch(in: title, options: [], range: range), m.numberOfRanges >= 2 {
                    let r = m.range(at: 1)
                    let s = ns.substring(with: r)
                    if let v = Int(s), v >= 0 && v < 10000 { return v }
                }
            }
        }
        return 0
    }
}
