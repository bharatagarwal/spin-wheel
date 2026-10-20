import Foundation
import PropertyBased
import Testing
@testable import HotPotatoCore

let awkwardCharacters = [
    "a", "B", "é", "e\u{301}", "🥔", "👩\u{200D}💻", "-", " ", "\t", "\n", "\r", "\r\n", "\u{2028}", "\u{00A0}", "\u{200B}", "\u{FEFF}",
]
let typedName = Gen.element(of: awkwardCharacters).map { $0 ?? "" }.array(of: 0...5).map { $0.joined() }

func looks(_ name: String) -> String {
    let shown = name.unicodeScalars.compactMap { scalar -> Character? in
        if scalar.properties.isWhitespace { return " " }
        return scalar.properties.isDefaultIgnorableCodePoint && scalar != "\u{200D}" ? nil : Character(scalar)
    }
    return String(shown).split(separator: " ").joined(separator: " ").precomposedStringWithCanonicalMapping
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

@Test func everyNameHasSomethingVisibleInIt() async {
    await propertyCheck(count: 1000, input: typedName) { typed in
        var team = Team(names: [])
        guard let name = team.add(typed) else { return }
        #expect(!looks(name).isEmpty, "\(name.unicodeScalars.map { "U+" + String($0.value, radix: 16, uppercase: true) })")
    }
}

@Test func namesThatLookTheSameAreOnePerson() async {
    await propertyCheck(count: 1000, input: typedName.array(of: 2...4)) { typed in
        var team = Team(names: [])
        for name in typed { _ = team.add(name) }
        let shown = team.names.map(looks)
        #expect(shown.count == Set(shown).count, "\(team.names.map(\.debugDescription))")
    }
}

@Test func aNameIsShownAsItWasTyped() async {
    await propertyCheck(count: 1000, input: typedName) { typed in
        var team = Team(names: [])
        guard let name = team.add(typed) else { return }
        #expect(looks(name) == looks(typed), "typed \(typed.debugDescription), kept \(name.debugDescription)")
    }
}
