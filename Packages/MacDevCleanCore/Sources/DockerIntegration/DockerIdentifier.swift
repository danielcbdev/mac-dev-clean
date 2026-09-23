import Domain
import Foundation

/// Strict validation for every identifier that reaches a command line.
///
/// Docker identifiers have narrow, documented shapes. Requiring the exact shape
/// means a value that could be read as an option — anything starting with `-` —
/// or that carries punctuation or control characters is refused before it can
/// become an argument, rather than being escaped and hoped about.
public enum DockerIdentifier {
    private static let hex = CharacterSet(charactersIn: "0123456789abcdef")

    /// 64 lowercase hexadecimal characters.
    public static func validateContainerID(_ value: String) throws {
        guard value.count == 64, isOnly(value, in: hex) else { throw PolicyError.unsupported }
    }

    /// `sha256:` followed by 64 lowercase hexadecimal characters.
    public static func validateImageID(_ value: String) throws {
        guard value.hasPrefix("sha256:") else { throw PolicyError.unsupported }
        let digest = String(value.dropFirst("sha256:".count))
        guard digest.count == 64, isOnly(digest, in: hex) else { throw PolicyError.unsupported }
    }

    /// An ASCII letter or digit, then letters, digits, `_`, `.` or `-`.
    public static func validateVolumeName(_ value: String) throws {
        guard let first = value.first, first.isASCII, first.isLetter || first.isNumber else {
            throw PolicyError.unsupported
        }
        guard value.count <= 255,
            value.dropFirst().allSatisfy({
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-")
            })
        else {
            throw PolicyError.unsupported
        }
    }

    /// An alphanumeric token, as the Buildx usage schema reports.
    public static func validateBuildCacheID(_ value: String) throws {
        guard !value.isEmpty, value.count <= 255,
            value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else {
            throw PolicyError.unsupported
        }
    }

    /// A context or builder name: never option-like, never punctuated.
    public static func validateName(_ value: String) throws {
        guard let first = value.first, first.isASCII, first.isLetter || first.isNumber else {
            throw PolicyError.unsupported
        }
        guard value.count <= 255,
            value.allSatisfy({
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-")
            })
        else {
            throw PolicyError.unsupported
        }
    }

    public static func validate(kind: DockerOperation, id: String) throws {
        switch kind {
        case .container: try validateContainerID(id)
        case .image: try validateImageID(id)
        case .volume: try validateVolumeName(id)
        case .buildCache: try validateBuildCacheID(id)
        }
    }

    private static func isOnly(_ value: String, in set: CharacterSet) -> Bool {
        value.unicodeScalars.allSatisfy { set.contains($0) }
    }
}
