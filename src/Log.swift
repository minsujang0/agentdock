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
    if let handle = try? FileHandle(forWritingTo: logURL) {
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: logURL)
    }
}
