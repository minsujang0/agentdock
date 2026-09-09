// Launched from Finder there is no console, so mirror everything to a file.

import Foundation

let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Logs/sessiondock.log")

func log(_ message: String) {
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "[\(stamp.string(from: Date()))] \(message)\n"
    print(line, terminator: "")
    fflush(stdout)
    guard let data = line.data(using: .utf8) else { return }
    // The log records what the dock did, not what anyone said. It still ends
    // up naming projects and session ids, so it is kept to its owner rather
    // than left at the 644 a fresh file is created with.
    if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
    }
    if let handle = try? FileHandle(forWritingTo: logURL) {
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: logURL)
    }
}
