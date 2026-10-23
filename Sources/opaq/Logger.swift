import os

enum Log {
    static let database = Logger(subsystem: "com.local.opaq", category: "database")
    static let watcher = Logger(subsystem: "com.local.opaq", category: "watcher")
    static let contacts = Logger(subsystem: "com.local.opaq", category: "contacts")
}
