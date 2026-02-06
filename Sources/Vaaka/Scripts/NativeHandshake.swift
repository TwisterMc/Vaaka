import Foundation

/// Small documentStart script that lets pages detect native message-handler availability
struct NativeHandshake {
    static let script = """
    (function(){
        // Mark native presence early so page scripts don't have to wait/queue.
        try {
            // Expose a ready flag to let other injected scripts short-circuit their fallback queues
            window.__vaaka_native_ready = true;

            // Provide a minimal helper for pages to test/flush native handlers
            window.__vaaka = window.__vaaka || {};
            window.__vaaka.hasHandler = function(name) {
                try { return !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]); } catch(e) { return false; }
            };

            // Ensure notification helper exists so pages can construct Notification objects without queuing
            window.__vaaka_notifications = window.__vaaka_notifications || {};

            // Ensure a pending queue exists for callers that can't reach native yet
            window.__vaaka_pendingMessages = window.__vaaka_pendingMessages || [];

            // Install lightweight shims for common handlers so page-head scripts can call postMessage synchronously
            try {
                if (window.webkit && window.webkit.messageHandlers) {
                    const names = ['badgeUpdate', 'notificationRequest'];
                    for (const n of names) {
                        if (typeof window.webkit.messageHandlers[n] === 'undefined') {
                            // create a shim that captures calls until the real handler appears
                            window.webkit.messageHandlers[n] = {
                                postMessage: function(payload) {
                                    try {
                                        window.__vaaka_pendingMessages.push({ name: n, payload: payload, queuedAt: Date.now() });
                                    } catch (e) { /* noop */ }
                                }
                            };
                        }
                    }
                }
            } catch(e) {
                // ignore; shimming is best-effort
            }

            // Try to flush any queued messages immediately if native handler is visible
            function tryFlush() {
                try {
                    const now = Date.now();
                    const remaining = [];
                    for (const m of window.__vaaka_pendingMessages) {
                        try {
                            if (window.__vaaka.hasHandler(m.name)) {
                                window.webkit.messageHandlers[m.name].postMessage(m.payload);
                            } else if (now - (m.queuedAt || 0) < 5000) {
                                // keep short-lived entries
                                remaining.push(m);
                            }
                        } catch (e) {
                            // if posting fails, keep for retry
                            if (now - (m.queuedAt || 0) < 5000) remaining.push(m);
                        }
                    }
                    window.__vaaka_pendingMessages = remaining;
                    return window.__vaaka_pendingMessages.length === 0;
                } catch (e) {
                    return false;
                }
            }

            // Attempt an immediate flush, then poll for a short period in case native appears shortly after
            tryFlush();
            const pollDeadline = Date.now() + 3000;
            const poll = setInterval(function() {
                if (tryFlush() || Date.now() > pollDeadline) clearInterval(poll);
            }, 100);

        } catch(e) {
            // Defensive: do not break page JS
        }
    })();
    """
}
