import Foundation
import AppKit

extension Notification.Name {
    static let DownloadsChanged = Notification.Name("Vaaka.DownloadsChanged")
    static let DownloadUpdated = Notification.Name("Vaaka.DownloadUpdated")
}

final class DownloadsManager: NSObject {
    static let shared = DownloadsManager()

    enum Status: String {
        case inProgress
        case completed
        case failed
        case cancelled
    }

    struct DownloadItem {
        let id: String
        let siteId: String
        let sourceURL: URL?
        var suggestedFilename: String
        var destinationURL: URL?
        var progress: Double // 0.0..1.0
        var status: Status
        var errorMessage: String?
    }

    private let queue = DispatchQueue(label: "vaaka.downloads")
    private var items: [String: DownloadItem] = [:]

    // Mapping for cancellable handlers (weak)
    private var cancellables: [String: WeakCancellable] = [:]

    // URLSession management for external (non-WKDownload) downloads
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.background(withIdentifier: "com.twistermc.Vaaka.downloads")
        cfg.sessionSendsLaunchEvents = false
        cfg.isDiscretionary = false
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var taskToId: [Int: String] = [:]

    private override init() {
        super.init()
    }

    // Basic CRUD
    func allItems() -> [DownloadItem] {
        return queue.sync { Array(items.values) }
    }

    func addExternalDownload(id: String, siteId: String, sourceURL: URL?, suggestedFilename: String, destination: URL?, taskIdentifier: Int?) {
        Logger.shared.debug("[DEBUG] DownloadsManager.addExternalDownload id=\(id) site=\(siteId) destination=\(destination?.path ?? "<nil>")")
        queue.sync {
            var d = DownloadItem(id: id, siteId: siteId, sourceURL: sourceURL, suggestedFilename: suggestedFilename, destinationURL: destination, progress: 0.0, status: .inProgress, errorMessage: nil)
            items[id] = d
            if let tid = taskIdentifier { taskToId[tid] = id }
        }
        notifyChanged()
    }

    func updateProgress(id: String, progress: Double) {
        queue.sync {
            if var d = items[id] {
                d.progress = progress
                items[id] = d
            }
        }
        notifyUpdate(id: id)
    }

    func setDestination(id: String, destination: URL) {
        queue.sync {
            if var d = items[id] {
                d.destinationURL = destination
                items[id] = d
            }
        }
        notifyUpdate(id: id)
    }

    func complete(id: String, destination: URL?) {
        queue.sync {
            if var d = items[id] {
                d.progress = 1.0
                d.status = .completed
                if let dest = destination { d.destinationURL = dest }
                items[id] = d
            }
        }
        notifyUpdate(id: id)
        notifyChanged()
        scheduleRemoval(id)
    }

    func fail(id: String, error: Error) {
        queue.sync {
            if var d = items[id] {
                d.status = .failed
                d.errorMessage = error.localizedDescription
                items[id] = d
            }
        }
        notifyUpdate(id: id)
        notifyChanged()
        scheduleRemoval(id)
    }

    func cancel(id: String) {
        // Ask the cancellable handler to cancel if present
        if let w = cancellables[id], let c = w.ref {
            c.cancelDownload()
        }

        // Also attempt to cancel any URLSession download task associated with this id
        let maybeTid = queue.sync { taskToId.first(where: { $0.value == id })?.key }
        if let tid = maybeTid {
            session.getAllTasks { tasks in
                for t in tasks where t.taskIdentifier == tid {
                    t.cancel()
                }
            }
        }

        queue.sync {
            if var d = items[id] {
                d.status = .cancelled
                items[id] = d
            }
        }
        notifyUpdate(id: id)
        notifyChanged()
        scheduleRemoval(id)
    }

    func registerCancellable(id: String, _ cancellable: Cancellable) {
        queue.sync { cancellables[id] = WeakCancellable(ref: cancellable) }
    }

    func unregisterCancellable(id: String) {
        queue.sync { cancellables.removeValue(forKey: id) }
    }

    // Start an external URL download (used for image Save As flow)
    @discardableResult
    func startExternalDownload(from url: URL, suggestedFilename: String, destination: URL?, siteId: String) -> String {
        let id = UUID().uuidString
        // If destination provided, use downloadTask(with:) but still track progress
        let task = session.downloadTask(with: url)
        addExternalDownload(id: id, siteId: siteId, sourceURL: url, suggestedFilename: suggestedFilename, destination: destination, taskIdentifier: task.taskIdentifier)
        task.resume()
        return id
    }

    private func notifyChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .DownloadsChanged, object: nil)
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .DownloadsChanged, object: nil) }
        }
    }

    private func notifyUpdate(id: String) {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .DownloadUpdated, object: nil, userInfo: ["id": id])
        } else {
            DispatchQueue.main.async { NotificationCenter.default.post(name: .DownloadUpdated, object: nil, userInfo: ["id": id]) }
        }
    }

    private func scheduleRemoval(_ id: String) {
        // Remove completed/failed items after a short delay so UI can show the final state briefly
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.queue.sync { self?.items.removeValue(forKey: id); self?.cancellables.removeValue(forKey: id); self?.taskToId = self?.taskToId.filter { $0.value != id } ?? [:] }
            self?.notifyChanged()
        }
    }
}

// Weak wrapper protocol to call cancel
protocol Cancellable: AnyObject {
    func cancelDownload()
}

private class WeakCancellable {
    weak var ref: Cancellable?
    init(ref: Cancellable?) { self.ref = ref }
}

// URLSession delegate methods to update progress + completion
extension DownloadsManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tid = downloadTask.taskIdentifier
        guard let id = queue.sync(execute: { taskToId[tid] }) else { return }

        // Move to destination if provided, otherwise move to Downloads
        var dest: URL? = nil
        queue.sync {
            dest = items[id]?.destinationURL
        }
        do {
            let fm = FileManager.default
            let final: URL
            if let d = dest {
                if fm.fileExists(atPath: d.path) { try fm.removeItem(at: d) }
                try fm.moveItem(at: location, to: d)
                final = d
            } else {
                let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let name = queue.sync { items[id]?.suggestedFilename ?? "download" }
                var candidate = downloads.appendingPathComponent(name)
                var idx = 1
                while fm.fileExists(atPath: candidate.path) {
                    let base = candidate.deletingPathExtension().lastPathComponent
                    let ext = candidate.pathExtension
                    let newName = ext.isEmpty ? "\(base)-\(idx)" : "\(base)-\(idx).\(ext)"
                    candidate = downloads.appendingPathComponent(newName)
                    idx += 1
                }
                try fm.moveItem(at: location, to: candidate)
                final = candidate
            }
            complete(id: id, destination: final)
            DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([final]) }
        } catch {
            fail(id: id, error: error)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let tid = downloadTask.taskIdentifier
        guard let id = queue.sync(execute: { taskToId[tid] }) else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        updateProgress(id: id, progress: progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // If error and was not handled in didFinishDownloadingTo
        if let err = error {
            let tid = task.taskIdentifier
            guard let id = queue.sync(execute: { taskToId[tid] }) else { return }
            fail(id: id, error: err)
        }
    }
}
