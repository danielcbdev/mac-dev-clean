#!/usr/bin/env swift

import Foundation

enum LocalizationCheckError: Error, LocalizedError {
    case invalidCatalog(String)

    var errorDescription: String? {
        switch self {
        case .invalidCatalog(let message): message
        }
    }
}

private let placeholderExpression = try! NSRegularExpression(
    pattern: #"%(?:([0-9]+)\$)?(?:lld|ld|d|@|f)"#
)

private func translationValues(in localization: Any) -> [String] {
    guard let dictionary = localization as? [String: Any] else { return [] }

    if let unit = dictionary["stringUnit"] as? [String: Any],
       unit["state"] as? String == "translated",
       let value = unit["value"] as? String,
       !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
        return [value]
    }

    return dictionary.values.flatMap(translationValues(in:))
}

private func placeholderSignature(in value: String) -> [String] {
    let range = NSRange(value.startIndex..., in: value)
    let matches = placeholderExpression.matches(in: value, range: range)
    return matches.enumerated().compactMap { index, match in
        guard let wholeRange = Range(match.range, in: value) else { return nil }
        let token = String(value[wholeRange])
        let position: String
        if match.range(at: 1).location != NSNotFound,
           let positionRange = Range(match.range(at: 1), in: value)
        {
            position = String(value[positionRange])
        } else {
            position = String(index + 1)
        }
        let type = token.split(separator: "$", maxSplits: 1).last ?? Substring(token)
        return "\(position):\(type)"
    }
}

/// Every `stringUnit` value under a localization, whatever its state and
/// whether or not it is empty. `translationValues` deliberately filters those
/// out; these rules exist to find them.
private func allValues(in localization: Any) -> [String] {
    guard let dictionary = localization as? [String: Any] else { return [] }
    if let unit = dictionary["stringUnit"] as? [String: Any] {
        return [unit["value"] as? String ?? ""]
    }
    return dictionary.values.flatMap(allValues(in:))
}

/// The plural categories a localization declares, e.g. `["one", "other"]`.
private func pluralCategories(in localization: Any) -> Set<String> {
    guard let dictionary = localization as? [String: Any],
          let variations = dictionary["variations"] as? [String: Any],
          let plural = variations["plural"] as? [String: Any]
    else { return [] }
    return Set(plural.keys)
}

private func check(_ path: String) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let object = try JSONSerialization.jsonObject(with: data)
    guard let catalog = object as? [String: Any],
          catalog["sourceLanguage"] as? String == "en",
          let strings = catalog["strings"] as? [String: Any]
    else {
        throw LocalizationCheckError.invalidCatalog("Catalog must have sourceLanguage en and strings.")
    }

    var problems: [String] = []
    for key in strings.keys.sorted() {
        guard let entry = strings[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any]
        else {
            problems.append("\(key): missing localizations")
            continue
        }

        // A value carrying Xcode's automatic grammar agreement annotation
        // reaches the screen intact wherever the annotation does not resolve.
        // That is the defect this rule exists for: the string was found and
        // translated, and the user still read the markup.
        for value in allValues(in: localizations) {
            if value.contains("^[") || value.contains("](inflect:") {
                problems.append("\(key): value carries inflection markup: \(value)")
                break
            }
        }

        // A key that carries a count must say how the count changes the words
        // around it. Without plural variations, "1 itens" is what ships.
        let englishPlural = pluralCategories(in: localizations["en"] as Any)
        let portuguesePlural = pluralCategories(in: localizations["pt-BR"] as Any)
        if key.contains("%lld") || key.contains("%ld") || key.contains("%d") {
            if englishPlural.isEmpty {
                problems.append("\(key): counts something but declares no plural variations")
            }
        }
        // Categories declared on one side only silently fall back to the key.
        if englishPlural != portuguesePlural {
            problems.append(
                "\(key): plural categories differ — en \(englishPlural.sorted()), "
                    + "pt-BR \(portuguesePlural.sorted())")
        }

        // An empty variation renders as nothing at all, which is worse than an
        // untranslated string: there is no text to report as wrong.
        for value in allValues(in: localizations)
        where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("\(key): has an empty value")
            break
        }

        let english = translationValues(in: localizations["en"] as Any)
        let portuguese = translationValues(in: localizations["pt-BR"] as Any)
        guard !english.isEmpty else {
            problems.append("\(key): missing translated English value")
            continue
        }
        guard !portuguese.isEmpty else {
            problems.append("\(key): missing translated Brazilian Portuguese value")
            continue
        }
        guard english.count == portuguese.count else {
            problems.append("\(key): locale variation counts differ")
            continue
        }
        for (englishValue, portugueseValue) in zip(english, portuguese) {
            if placeholderSignature(in: englishValue) != placeholderSignature(in: portugueseValue) {
                problems.append("\(key): format placeholders differ between en and pt-BR")
                break
            }
        }

    }

    if !problems.isEmpty {
        throw LocalizationCheckError.invalidCatalog(problems.joined(separator: "\n"))
    }
    print("Localization catalog valid: \(strings.count) keys")
}

do {
    let path = CommandLine.arguments.dropFirst().first
        ?? "MacDevCleanApp/Resources/Localizable.xcstrings"
    try check(path)
} catch {
    fputs("Localization check failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
