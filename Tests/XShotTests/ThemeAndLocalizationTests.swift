import SwiftUI
import XCTest
@testable import XShot

final class ThemeAndLocalizationTests: XCTestCase {
    private func extractFormatSpecifiers(from string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "%(?:[0-9]+\\$)?(?:[0-9]*\\.?[0-9]*)?[@dfsu]") else {
            return []
        }
        let ns = string as NSString
        return regex.matches(in: string, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }

    func testAllLocalizationKeysExistWithMatchingFormatSpecifiersInAllTenLanguages() {
        XCTAssertEqual(AppLanguage.concreteLanguages.count, 10)
        guard let enDict = L10n.table[.en] else {
            XCTFail("Missing English reference localization table")
            return
        }

        for lang in AppLanguage.concreteLanguages {
            guard let dict = L10n.table[lang] else {
                XCTFail("Missing localization table for language \(lang.rawValue)")
                continue
            }
            for key in L10nKey.allCases {
                let value = dict[key]
                XCTAssertNotNil(value, "Missing key '\(key.rawValue)' in \(lang.rawValue)")
                XCTAssertFalse(
                    (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Empty translation for key '\(key.rawValue)' in \(lang.rawValue)"
                )
                if let enVal = enDict[key], let localizedVal = value {
                    let expectedSpecs = extractFormatSpecifiers(from: enVal)
                    let actualSpecs = extractFormatSpecifiers(from: localizedVal)
                    XCTAssertEqual(
                        actualSpecs,
                        expectedSpecs,
                        "Format specifier mismatch for key '\(key.rawValue)' in \(lang.rawValue): expected \(expectedSpecs), got \(actualSpecs)"
                    )
                }
            }
        }
    }

    func testSystemLanguageAutoResolution() {
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["zh-Hans-CN"]), .zhHans)
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["zh-Hant-TW"]), .zhHant)
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["en-US"]), .en)
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["ja-JP"]), .ja)
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["ko-KR"]), .ko)
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["es-ES"]), .es)
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["fr-FR"]), .fr)
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["de-DE"]), .de)
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["pt-BR"]), .pt)
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["ru-RU"]), .ru)
        // Unsupported language falls back gracefully to English
        XCTAssertEqual(AppLanguage.system.resolvedConcreteLanguage(preferredLanguages: ["it-IT"]), .en)
    }

    func testLightAndDarkStudioPalettesResolveProperly() {
        let light = StudioPalette.resolved(for: .light)
        let dark = StudioPalette.resolved(for: .dark)
        XCTAssertFalse(light.isDark)
        XCTAssertTrue(dark.isDark)
        XCTAssertEqual(AppAppearanceMode.light.swiftUIColorScheme, .light)
        XCTAssertEqual(AppAppearanceMode.dark.swiftUIColorScheme, .dark)
        XCTAssertNil(AppAppearanceMode.system.swiftUIColorScheme)

        // Explicit mode overrides environment scheme immediately (prevents Light/Dark mismatch on first frame)
        XCTAssertEqual(AppAppearanceMode.dark.resolvedColorScheme(environment: .light), .dark)
        XCTAssertEqual(AppAppearanceMode.light.resolvedColorScheme(environment: .dark), .light)
        XCTAssertEqual(AppAppearanceMode.system.resolvedColorScheme(environment: .dark), .dark)
        XCTAssertEqual(AppAppearanceMode.system.resolvedColorScheme(environment: .light), .light)
        XCTAssertTrue(StudioPalette.resolved(mode: .dark, environment: .light).isDark)
        XCTAssertFalse(StudioPalette.resolved(mode: .light, environment: .dark).isDark)
    }
}
