import Foundation

enum LibArchiveReadErrorMapper {
    static func map(
        archiveURL: URL,
        message: String,
        engine: String,
        operation: String
    ) -> ArchiveError {
        if let passwordError = passwordError(archiveURL: archiveURL, message: message) {
            return passwordError
        }

        return .engineFailure(
            engine: engine,
            message: "\(operation): \(message)"
        )
    }

    static func passwordError(archiveURL: URL, message: String) -> ArchiveError? {
        let lowercasedMessage = message.lowercased()
        guard lowercasedMessage.contains("passphrase")
            || lowercasedMessage.contains("password") else {
            return nil
        }

        if lowercasedMessage.contains("incorrect")
            || lowercasedMessage.contains("invalid")
            || lowercasedMessage.contains("wrong") {
            return .incorrectArchivePassword(archiveURL)
        }

        return .encryptedArchive(archiveURL)
    }
}
