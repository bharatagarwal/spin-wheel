import Foundation
import PropertyBased
import Testing
@testable import HotPotatoCore

let awkwardCharacters = [
    "a", "B", "é", "e\u{301}", "🥔", "👩\u{200D}💻", "-",
    " ", "\t", "\n", "\r", "\r\n", "\u{2028}", "\u{00A0}", "\u{200B}", "\u{FEFF}"
]
let typedName = Gen.element(of: awkwardCharacters).map { $0 ?? "" }.array(of: 0...5).map { $0.joined() }

func looks(_ typed: String) -> String {
    let shown = typed.unicodeScalars.compactMap { scalar -> Character? in
        if scalar.properties.isWhitespace { return " " }
        return scalar.properties.isDefaultIgnorableCodePoint && scalar != "\u{200D}" ? nil : Character(scalar)
    }
    return String(shown).split(separator: " ").joined(separator: " ").precomposedStringWithCanonicalMapping
}

@Test func aNameIsWhatWasTypedAsItLooks() async {
    await propertyCheck(count: 1000, input: typedName) { typed in
        let name = Name(typed)
        #expect((name == nil) == looks(typed).isEmpty, "typed \(typed.debugDescription)")
        if let name {
            #expect(looks(name.text) == looks(typed),
                    "typed \(typed.debugDescription), kept \(name.text.debugDescription)")
        }
    }
}

@Test func cleaningANameAgainChangesNothing() async {
    await propertyCheck(count: 1000, input: typedName) { typed in
        guard let name = Name(typed) else { return }
        #expect(Name(name.text) == name && Name(name.text)?.text == name.text, "\(name.text.debugDescription)")
    }
}

@Test func twoTypedNamesAreOnePersonExactlyWhenTheyLookTheSame() async {
    await propertyCheck(count: 2000, input: typedName, typedName) { first, second in
        guard let firstName = Name(first), let secondName = Name(second) else { return }
        #expect((firstName == secondName) == (looks(first) == looks(second)),
                "\(first.debugDescription) and \(second.debugDescription)")
    }
}

@Test func aSavedTeamLoadsBackUnchanged() async {
    await propertyCheck(count: 1000, input: typedName.array(of: 0...6)) { typed in
        var team = Team.load(from: scratchDefaults(), orFrom: [])
        for name in typed { _ = team.add(name) }
        let defaults = scratchDefaults()
        team.save(to: defaults)
        #expect(Team.load(from: defaults, orFrom: []).names == team.names)
    }
}

struct TeamSavedBeforeNamesWereCleaned {
    var names: [String] = []

    mutating func add(_ typed: String) {
        let name = typed.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !names.contains(name) else { return }
        names.append(name)
    }

    var saved: String { names.joined(separator: "\n") }
}

@Test func aTeamSavedByTheOldVersionLoadsWithEveryLineKept() async {
    await propertyCheck(count: 1000, input: typedName.array(of: 0...6)) { typed in
        var old = TeamSavedBeforeNamesWereCleaned()
        for name in typed { old.add(name) }
        let defaults = scratchDefaults()
        defaults.set(old.saved, forKey: "names")
        var expected: [Name] = []
        for line in old.names.flatMap({ $0.split(whereSeparator: \.isNewline) }) {
            if let name = Name(line), !expected.contains(name) { expected.append(name) }
        }
        #expect(Team.load(from: defaults, orFrom: []).names == expected, "old save \(old.saved.debugDescription)")
    }
}
