import Foundation

struct NotificationInterceptor {
    static let script = """
    (function() {
        const isSlack = window.location.hostname.includes('slack.com');
        const isGmail = window.location.hostname.includes('mail.google.com');
        
        console.log('[Vaaka] Notification simulator enabled for:', window.location.hostname);
        
        // For Slack, hint desktop mode
        if (isSlack) {
            window.slackDebug = { desktop: true };
        }
        
        // Store original for fallback
        const OriginalNotification = window.Notification;
        
        // Override Notification API
        class NotificationProxy {
            constructor(title, options = {}) {
                console.log('[Vaaka] Notification created:', title);

                // Ensure global map exists
                if (!window.__vaaka_notifications) window.__vaaka_notifications = {};
                const id = 'vaaka-' + Math.random().toString(36).slice(2);

                const mock = {
                    title: title,
                    body: options.body || "",
                    tag: options.tag || "",
                    close: function() {
                        try {
                            if (window.webkit && window.webkit.messageHandlers.notificationRequest) {
                                window.webkit.messageHandlers.notificationRequest.postMessage({ type: 'close', id: id });
                            }
                        } catch(e) {}
                    },
                    onclick: null,
                    onclose: null
                };

                window.__vaaka_notifications[id] = mock;

                // Send to native handler with id so the native side can map clicks back
                if (window.webkit && window.webkit.messageHandlers.notificationRequest) {
                    window.webkit.messageHandlers.notificationRequest.postMessage({
                        type: 'show',
                        id: id,
                        title: title,
                        body: options.body || "",
                        icon: options.icon || "",
                        tag: options.tag || ""
                    });
                }

                return mock;
            }

            static get permission() { 
                return window.nativeNotificationPermission || 'default';
            }

            static requestPermission(callback) {
                console.log('[Vaaka] Notification.requestPermission() called');
                // Store callback and return a promise that resolves when native answers
                if (callback) window.notificationPermissionCallback = callback;
                return new Promise(function(resolve) {
                    window.__vaaka_permissionResolver = resolve;
                    try {
                        if (window.webkit && window.webkit.messageHandlers.notificationRequest) {
                            window.webkit.messageHandlers.notificationRequest.postMessage({ type: 'permissionRequest' });
                        }
                    } catch(e) { resolve('denied'); }
                });
            }
        }
        
        // Mock minimal Push/ServiceWorker ONLY for sites that check them
        class PushManagerProxy {
            async subscribe(options) {
                console.log('[Vaaka] PushManager.subscribe - returning mock subscription');
                return {
                    endpoint: "https://vaaka-simulator.local/push",
                    expirationTime: null,
                    options: options || {},
                    getKey: () => new Uint8Array(0),
                    toJSON: function() { return { endpoint: this.endpoint, keys: {} }; },
                    unsubscribe: async () => true
                };
            }
            
            async getSubscription() { return null; }
            async permissionState() { return "granted"; }
        }
        
        class ServiceWorkerRegistrationProxy {
            constructor() {
                this.pushManager = new PushManagerProxy();
                this.active = { state: "activated" };
                this.scope = window.location.origin + "/";
            }
            
            async showNotification(title, options) {
                // Delegate to Notification API
                new NotificationProxy(title, options);
            }
            
            async getNotifications() { return []; }
            async update() { return this; }
            async unregister() { return true; }
        }
        
        class ServiceWorkerContainerProxy {
            constructor() {
                this.controller = { state: "activated" };
                this.ready = Promise.resolve(new ServiceWorkerRegistrationProxy());
            }
            
            async register(scriptURL, options) {
                console.log('[Vaaka] ServiceWorker.register called');
                return new ServiceWorkerRegistrationProxy();
            }
            
            async getRegistration() { return new ServiceWorkerRegistrationProxy(); }
            async getRegistrations() { return [new ServiceWorkerRegistrationProxy()]; }
            
            addEventListener() {}
            removeEventListener() {}
        }
        
        // Apply overrides
        window.Notification = NotificationProxy;
        
        // Only add ServiceWorker if missing
        if (!navigator.serviceWorker) {
            Object.defineProperty(navigator, 'serviceWorker', {
                value: new ServiceWorkerContainerProxy(),
                configurable: true
            });
        }
        
        // Slack-specific intercept (only if Slack object exists)
        if (isSlack) {
            let attempts = 0;
            const interceptSlack = setInterval(() => {
                if (window.TS?.desktop?.notifications?.notifyNewMessage) {
                    clearInterval(interceptSlack);
                    const orig = window.TS.desktop.notifications.notifyNewMessage;
                    window.TS.desktop.notifications.notifyNewMessage = function(data) {
                        console.log('[Vaaka] Slack notification:', data);
                        new NotificationProxy(data.title || 'Slack', {
                            body: data.body || data.message || ''
                        });
                        if (orig) orig.apply(this, arguments);
                    };
                }
                if (++attempts > 50) clearInterval(interceptSlack);
            }, 100);
        }
        
        console.log('[Vaaka] Notification system ready');
    })();
    """
}
