import Foundation

extension URL {
    var displayName: String {
        lastPathComponent.isEmpty ? path : lastPathComponent
    }

    var displayPath: String {
        path(percentEncoded: false)
    }
}
