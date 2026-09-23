import Domain
import Foundation

/// Decodes Docker's machine-readable output.
///
/// The rule throughout: **unrecognised means refused, not permitted.** A
/// missing field, a changed shape or a number that will not fit produces an
/// error or an explicit unknown. Nothing here guesses, and no missing boolean is
/// read as the permissive value.
public enum DockerParser {

    // MARK: - Listings

    public static func containers(_ data: Data) throws -> [ContainerDTO] {
        try lines(data).map { object in
            guard let id = object.string("ID"), !id.isEmpty else {
                throw PolicyError.unsupported
            }
            return ContainerDTO(
                id: id,
                image: object.string("Image") ?? "",
                names: object.string("Names") ?? "",
                // An absent state is not assumed to be "stopped".
                state: object.string("State") ?? "unknown",
                mounts: splitList(object.string("Mounts"))
            )
        }
    }

    public static func images(_ data: Data) throws -> [ImageDTO] {
        try lines(data).map { object in
            guard let id = object.string("ID"), !id.isEmpty else {
                throw PolicyError.unsupported
            }
            return ImageDTO(
                id: id,
                repository: object.string("Repository") ?? "<none>",
                tag: object.string("Tag") ?? "<none>"
            )
        }
    }

    public static func volumes(_ data: Data) throws -> [VolumeDTO] {
        try lines(data).map { object in
            guard let name = object.string("Name"), !name.isEmpty else {
                throw PolicyError.unsupported
            }
            return VolumeDTO(
                name: name,
                // An unknown driver is not the local driver, so it stays
                // ineligible.
                driver: object.string("Driver") ?? "unknown",
                scope: object.string("Scope") ?? "unknown"
            )
        }
    }

    public static func buildCache(_ data: Data) throws -> [BuildCacheDTO] {
        try lines(data).map { object in
            guard let id = object.string("ID"), !id.isEmpty else {
                throw PolicyError.unsupported
            }
            let measured = object.byteCount("Size")
            return BuildCacheDTO(
                id: id,
                size: measured.value,
                // Absent means not reclaimable.
                reclaimable: object.bool("Reclaimable") ?? false,
                // Absent means assume shared, which keeps it out of exact totals.
                shared: object.bool("Shared") ?? true,
                // Absent means assume mutable, which keeps it ineligible.
                mutable: object.bool("Mutable") ?? true,
                sizeIssue: measured.issue
            )
        }
    }

    // MARK: - Inspections

    public static func containerDetails(_ data: Data) throws -> [ContainerDetailDTO] {
        try array(data).map { object in
            guard let id = object.string("Id"), !id.isEmpty else {
                throw PolicyError.unsupported
            }
            let state = object.object("State")
            let mounts = (object.raw["Mounts"] as? [[String: Any]]) ?? []
            return ContainerDetailDTO(
                id: id,
                imageID: object.string("Image") ?? "",
                running: state?.bool("Running") ?? true,
                mountNames: mounts.compactMap { $0["Name"] as? String },
                sizeRootFs: object.byteCount("SizeRootFs").value
            )
        }
    }

    public static func imageDetails(_ data: Data) throws -> [ImageDetailDTO] {
        try array(data).map { object in
            guard let id = object.string("Id"), !id.isEmpty else {
                throw PolicyError.unsupported
            }
            return ImageDetailDTO(
                id: id,
                size: object.byteCount("Size").value,
                repoTags: (object.raw["RepoTags"] as? [String]) ?? [],
                repoDigests: (object.raw["RepoDigests"] as? [String]) ?? []
            )
        }
    }

    public static func volumeDetails(_ data: Data) throws -> [VolumeDetailDTO] {
        try array(data).map { object in
            guard let name = object.string("Name"), !name.isEmpty else {
                throw PolicyError.unsupported
            }
            // Docker reports -1 for "not calculated". That is unknown, not zero.
            let usage = object.object("UsageData")
            return VolumeDetailDTO(
                name: name,
                driver: object.string("Driver") ?? "unknown",
                size: usage?.byteCount("Size").value
            )
        }
    }

    // MARK: - Shapes

    /// Newline-delimited JSON objects, which is what `--format {{json .}}` and
    /// `buildx du --format=json` both emit.
    private static func lines(_ data: Data) throws -> [JSONObject] {
        let text = String(decoding: data, as: UTF8.self)
        var result: [JSONObject] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard
                let parsed = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
                let object = parsed as? [String: Any]
            else {
                throw PolicyError.unsupported
            }
            result.append(JSONObject(raw: object))
        }
        return result
    }

    /// A JSON array, which is what `inspect` emits.
    private static func array(_ data: Data) throws -> [JSONObject] {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
            throw PolicyError.unsupported
        }
        if let objects = parsed as? [[String: Any]] {
            return objects.map { JSONObject(raw: $0) }
        }
        if let object = parsed as? [String: Any] {
            return [JSONObject(raw: object)]
        }
        throw PolicyError.unsupported
    }

    private static func splitList(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        return value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// A decoded JSON object with accessors that refuse rather than coerce.
struct JSONObject {
    let raw: [String: Any]

    func string(_ key: String) -> String? {
        raw[key] as? String
    }

    func bool(_ key: String) -> Bool? {
        // A JSON boolean only. A string "true" is a different shape and is not
        // quietly accepted.
        guard let value = raw[key] as? NSNumber,
            CFGetTypeID(value) == CFBooleanGetTypeID()
        else {
            return raw[key] as? Bool
        }
        return value.boolValue
    }

    func object(_ key: String) -> JSONObject? {
        (raw[key] as? [String: Any]).map { JSONObject(raw: $0) }
    }

    /// Docker encodes sizes as a number in some places and a decimal string in
    /// others. Both are accepted; anything negative, non-numeric or too large is
    /// reported as unknown with a reason.
    func byteCount(_ key: String) -> (value: UInt64?, issue: String?) {
        guard let value = raw[key] else { return (nil, nil) }

        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed != "N/A" else {
                return (nil, "issue.docker.sizeUnavailable")
            }
            if trimmed.hasPrefix("-") { return (nil, "issue.docker.sizeNegative") }
            guard let parsed = UInt64(trimmed) else {
                // A human-readable size such as "1.09GB" is not an exact answer
                // and is never turned into one.
                return (nil, "issue.docker.sizeNotExact")
            }
            return (parsed, nil)
        }

        if let number = value as? NSNumber {
            let doubled = number.doubleValue
            if doubled < 0 { return (nil, "issue.docker.sizeNegative") }
            if doubled > Double(UInt64.max) { return (nil, "issue.docker.sizeOverflow") }
            return (UInt64(doubled), nil)
        }

        return (nil, "issue.docker.sizeUnsupported")
    }
}
