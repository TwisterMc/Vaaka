import Foundation

struct ConsoleForwarder {
    static let script = """
    (function() {
        function send(level, args) {
            try {
                const parts = Array.from(args).map(a => {
                    try { return (typeof a === 'object' ? JSON.stringify(a) : String(a)); } catch (e) { return String(a); }
                });
                const message = parts.join(' ');
                const stack = (new Error()).stack || '';
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.consoleMessage) {
                    window.webkit.messageHandlers.consoleMessage.postMessage({ level: level, message: message, stack: stack });
                }
            } catch(e) { /* best-effort */ }
        }

        const origLog = console.log.bind(console);
        console.log = function() { send('log', arguments); try { origLog.apply(console, arguments); } catch(e) {} };
        const origWarn = console.warn.bind(console);
        console.warn = function() { send('warn', arguments); try { origWarn.apply(console, arguments); } catch(e) {} };
        const origError = console.error.bind(console);
        console.error = function() { send('error', arguments); try { origError.apply(console, arguments); } catch(e) {} };

        window.addEventListener('error', function(e) {
            try {
                const msg = (e && e.message) ? e.message : String(e);
                const src = (e && e.filename) ? (e.filename + ':' + e.lineno + ':' + e.colno) : '';
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.consoleMessage) {
                    window.webkit.messageHandlers.consoleMessage.postMessage({ level: 'error', message: msg + ' ' + src, stack: (e && e.error && e.error.stack) ? e.error.stack : '' });
                }
            } catch(e) { }
        }, true);

        // Also capture unhandledrejection
        window.addEventListener('unhandledrejection', function(ev) {
            try {
                const reason = ev && ev.reason ? (typeof ev.reason === 'object' ? JSON.stringify(ev.reason) : String(ev.reason)) : 'rejection';
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.consoleMessage) {
                    window.webkit.messageHandlers.consoleMessage.postMessage({ level: 'error', message: 'UnhandledRejection: ' + reason, stack: '' });
                }
            } catch(e) { }
        }, true);
    })();
    """
}
