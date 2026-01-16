import Foundation

struct ContextMenuInterceptor {
    static let script = """
    (function() {
        // Listen for right-clicks; if the target is an <img> we capture the src and notify native.
        document.addEventListener('contextmenu', function(e) {
            try {
                var el = e.target;
                // walk up to find an <img>
                while (el && el.nodeType === 1 && el.tagName.toLowerCase() !== 'img') {
                    el = el.parentElement;
                }
                if (el && el.tagName && el.tagName.toLowerCase() === 'img') {
                    var src = el.currentSrc || el.src;
                    if (src) {
                        // inform native of an image context so it can offer a Save dialog
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.contextMenu) {
                            window.webkit.messageHandlers.contextMenu.postMessage({ type: 'image', src: src });
                            // Prevent the default context menu so the native menu is shown instead
                            e.preventDefault();
                        }
                    }
                }
            } catch (ex) {
                try { console.log('[Vaaka] context menu interceptor error:', ex); } catch (e) {}
            }
        }, true);

        console.log('[Vaaka] Context menu interceptor installed');
    })();
    """
}
