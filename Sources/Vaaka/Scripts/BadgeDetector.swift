import Foundation

struct BadgeDetector {
    static let script = """
    (function() {
        const isSlack = window.location.hostname.includes('slack.com');
        const isGmail = window.location.hostname.includes('mail.google.com');
        
        let lastReportedCount = -1;
        
        function detectBadge() {
            let count = 0;
            
            // Priority 1: Title-based detection (most reliable)
            const title = document.title;
            const titleMatch = title.match(/\\((\\d+)\\)/) || title.match(/\\|\\s*(\\d+)/);
            if (titleMatch) {
                count = parseInt(titleMatch[titleMatch.length - 1]);
            }
            
            // Priority 2: Site-specific DOM fallbacks (only if title failed)
            if (count === 0 && isGmail) {
                try {
                    const inboxNav = document.querySelector('[role="navigation"] [title*="Inbox"]');
                    if (inboxNav) {
                        const match = inboxNav.textContent.match(/\\d+/);
                        if (match) count = parseInt(match[0]);
                    }
                } catch (e) {
                    console.log('[Vaaka] Gmail badge detection error:', e);
                }
            }
            
            if (count === 0 && isSlack) {
                try {
                    const badge = document.querySelector('.p-ia__sidebar_header__count, [data-qa="unreads_count"]');
                    if (badge) {
                        const match = badge.textContent.match(/\\d+/);
                        if (match) count = parseInt(match[0]);
                    }
                } catch (e) {
                    console.log('[Vaaka] Slack badge detection error:', e);
                }
            }
            
            // Only report if count changed
            if (count !== lastReportedCount) {
                lastReportedCount = count;
                if (window.webkit?.messageHandlers?.badgeUpdate) {
                    window.webkit.messageHandlers.badgeUpdate.postMessage({ count: count });
                }
            }
        }
        
        // Initial detection
        detectBadge();
        
        // Poll every 5 seconds (conservative)
        setInterval(detectBadge, 5000);
        
        // Watch title changes
        const titleEl = document.querySelector('title');
        if (titleEl) {
            new MutationObserver(detectBadge).observe(titleEl, {
                childList: true,
                characterData: true,
                subtree: true
            });
        }
        
        console.log('[Vaaka] Badge detector active');
    })();
    """
}
