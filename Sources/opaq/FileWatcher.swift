import Foundation

final class FileWatcher: @unchecked Sendable {
    private let walPath: String
    private let dbPath: String

    private var walSource: DispatchSourceFileSystemObject?
    private var dbSource: DispatchSourceFileSystemObject?

    private var walFd: Int32 = -1
    private var dbFd: Int32 = -1

    private let queue = DispatchQueue(label: "com.local.opaq.filewatcher", qos: .utility)
    private var debounceTimer: DispatchSourceTimer?
    private let lock = NSLock()
    private var isRunning = false

    private var onChange: (@Sendable () -> Void)?

    init(
        walPath: String = DatabaseService.defaultWalPath,
        dbPath: String = DatabaseService.defaultDbPath
    ) {
        self.walPath = walPath
        self.dbPath = dbPath
    }

    deinit {
        stop()
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        self.onChange = onChange
        isRunning = true
        lock.unlock()

        queue.async { [weak self] in
            self?.setupWatchers()
        }
    }

    func stop() {
        lock.lock()
        isRunning = false
        debounceTimer?.cancel()
        debounceTimer = nil
        onChange = nil

        let wal = walSource
        let db = dbSource
        walSource = nil
        dbSource = nil
        walFd = -1
        dbFd = -1
        lock.unlock()

        wal?.cancel()
        db?.cancel()
    }

    private func stillRunning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    private func setupWatchers() {
        watchWalFile()
        watchDbFile()
    }

    private func watchWalFile() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        let previous = walSource
        walSource = nil
        walFd = -1
        lock.unlock()
        previous?.cancel()

        guard FileManager.default.fileExists(atPath: walPath) else {
            queue.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self else { return }
                guard self.stillRunning() else { return }
                self.watchWalFile()
            }
            return
        }

        guard let fd = openWatchDescriptor(path: walPath) else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let data = source.data
            if data.contains(.delete) || data.contains(.rename) {
                self.queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self else { return }
                    guard self.stillRunning() else { return }
                    self.watchWalFile()
                }
            }
            self.triggerDebouncedChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        install(source, fd: fd, isWal: true)
    }

    private func watchDbFile() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        let previous = dbSource
        dbSource = nil
        dbFd = -1
        lock.unlock()
        previous?.cancel()

        guard FileManager.default.fileExists(atPath: dbPath) else { return }
        guard let fd = openWatchDescriptor(path: dbPath) else { return }

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

        install(source, fd: fd, isWal: false)
    }

    private func install(_ source: DispatchSourceFileSystemObject, fd: Int32, isWal: Bool) {
        lock.lock()
        if !isRunning {
            lock.unlock()
            // A source that was never resumed does not run its cancel handler.
            source.cancel()
            source.resume()
            return
        }
        if isWal {
            walFd = fd
            walSource = source
        } else {
            dbFd = fd
            dbSource = source
        }
        source.resume()
        lock.unlock()
    }

    private func openWatchDescriptor(path: String) -> Int32? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            let err = errno
            let message = String(cString: strerror(err))
            Log.watcher.error("failed to open \(path, privacy: .public): \(message, privacy: .public)")
            return nil
        }
        return fd
    }

    private func triggerDebouncedChange() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }

        debounceTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(400))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let running = self.isRunning
            let callback = self.onChange
            self.debounceTimer = nil
            self.lock.unlock()
            guard running else { return }
            callback?()
        }
        debounceTimer = timer
        timer.resume()
        lock.unlock()
    }
}
