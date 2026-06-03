//
//  AppLocalization.swift
//  PayGuard
//
//  Created by Ali Ozkul on 02.05.26.
//

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case tr
    case de

    static let storageKey = "selectedAppLanguage"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var displayName: String {
        switch self {
        case .en:
            "English"
        case .tr:
            "Türkçe"
        case .de:
            "Deutsch"
        }
    }

    var flag: String {
        switch self {
        case .en:
            "🇬🇧"
        case .tr:
            "🇹🇷"
        case .de:
            "🇩🇪"
        }
    }

    var shortLabel: String {
        rawValue.uppercased()
    }

    var selectionLabel: String {
        "\(flag) \(displayName)"
    }

    static var fallback: AppLanguage {
        guard let code = Locale.preferredLanguages.first?.prefix(2).lowercased() else {
            return .en
        }
        return AppLanguage(rawValue: code) ?? .en
    }

    static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        return stored.flatMap(AppLanguage.init(rawValue:)) ?? fallback
    }

    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

func PMLocalized(_ key: String, _ args: CVarArg...) -> String {
    let language = AppLanguage.current
    let format = language.bundle.localizedString(forKey: key, value: key, table: nil)
    guard !args.isEmpty else { return format }
    return String(format: format, locale: language.locale, arguments: args)
}

extension String {
    var pmLocalized: String {
        PMLocalized(self)
    }

    var localizedKey: LocalizedStringKey {
        LocalizedStringKey(self)
    }
}
