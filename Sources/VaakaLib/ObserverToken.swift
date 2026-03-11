import Foundation

/// Simple RAII wrapper for NotificationCenter observer tokens.
/// Creating an `ObserverToken` will automatically remove the token when it deallocates.
final class ObserverToken {
    private let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }

    func invalidate() {
        NotificationCenter.default.removeObserver(token)
    }
}
