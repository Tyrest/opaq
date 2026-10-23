import Foundation

public final class FileWatcher: @unchecked Sendable {
    private let walPath: String
    private let dbPath: String

    private var walSource: DispatchSourceFileSystemObject?
    private var dbSource: DispatchSourceFileSystemObject?

    private var walFd: Int32 = -1
    private var dbFd: Int32 = -1

    private let queue = DispatchQueue(label: "com.local.opaq.filewatcher", qos: .utility)
    private var debounceTimer: DispatchSourceTimer?
    private let lock = NSLock()

    private var onChange: (@Sendable () -> Void)?

    public init(
        walPath: String = DatabaseService.defaultWalPath,
        dbPath: String = DatabaseService.defaultDbPath
    ) {
        self.walPath = walPath
        self.dbPath = dbPath
    }

    deinit {
        stop()
    }

    public func start(onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        self.onChange = onChange
        lock.unlock()

        queue.async { [weak self] in
            self?.setupWatchers()
        }
    }

    public func stop() {
        lock.lock()
        debounceTimer?.cancel()
        debounceTimer = nil
        onChange = nil

        walSource?.cancel()
        walSource = nil

        dbSource?.cancel()
        dbSource = nil

        if walFd >= 0 {
            close(walFd)
            walFd = -1
        }
        if dbFd >= 0 {
            close(dbFd)
            dbFd = -1
        }
        lock.unlock()
    }

    private func setupWatchers() {
        watchWalFile()
        watchDbFile()
    }

    private func watchWalFile() {
        if walFd >= 0 {
            close(walFd)
            walFd = -1
        }
        walSource?.cancel()
        walSource = nil

        guard FileManager.default.fileExists(atPath: walPath) else {
            // WAL file may not exist yet, retry after a delay
            queue.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.watchWalFile()
            }
            return
        }

        let fd = open(walPath, O_EVTONLY)
        guard fd >= 0 else { return }
        walFd = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let data = source.data
            if data.contains(.delete) || data.contains(.rename) {
                // WAL file rotated or deleted, re-arm
                self.queue.asyncAfter(deadline: .now() + 1.0) {
                    self.watchWalFile()
                }
            }
            self.triggerDebouncedChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        walSource = source
        source.resume()
    }

    private func watchDbFile() {
        if dbFd >= 0 {
            close(dbFd)
            dbFd = -1
        }
        dbSource?.cancel()
        dbSource = nil

        guard FileManager.default.fileExists(atPath: dbPath) else { return }

        let fd = open(dbPath, O_EVTONLY)
        guard fd >= 0 else { return }
        dbFd = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.triggerDebouncedChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        dbSource = source
        source.resume()
    }

    private func triggerDebouncedChange() {
        lock.lock()
        defer { lock.unlock() }

        debounceTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(400))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let callback = self.onChange
            self.debounceTimer = nil
            self.lock.unlock()

            callback?()
        }
        debounceTimer = timer
        timer.resume()
    }
}
