//
//  Formatters.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Foundation
import SwiftUI

enum PayGuardFormatters {
    static var mediumDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = AppLanguage.current.locale
        return formatter
    }

    static var shortTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = AppLanguage.current.locale
        return formatter
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }

    func currencyString(code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = AppLanguage.current.locale
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "\(self)"
    }
}

extension Collection where Element == Int {
    var reminderSummary: String {
        map { "\($0)d" }.joined(separator: " • ")
    }
}

extension Date {
    var shortRelativeDescription: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return PMLocalized("Today")
        }
        if calendar.isDateInTomorrow(self) {
            return PMLocalized("Tomorrow")
        }

        let days = calendar.dateComponents([.day], from: .now.startOfDay, to: self.startOfDay).day ?? 0
        if days > 0 {
            return PMLocalized("In %d days", days)
        }
        if days < 0 {
            return PMLocalized("%d days ago", -days)
        }
        return PayGuardFormatters.mediumDate.string(from: self)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var hourComponent: Int {
        Calendar.current.component(.hour, from: self)
    }

    var minuteComponent: Int {
        Calendar.current.component(.minute, from: self)
    }

    var shortTimeString: String {
        PayGuardFormatters.shortTime.string(from: self)
    }

    static func reminderClock(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? .now
    }
}

extension View {
    func payGuardCardStyle() -> some View {
        modifier(PayGuardCardModifier())
    }

    func payGuardTextInputStyle() -> some View {
        modifier(PayGuardTextInputStyle())
    }

    func payGuardListSectionStyle() -> some View {
        modifier(PayGuardListSectionModifier())
    }

    func payGuardNavigationChrome() -> some View {
        modifier(PayGuardNavigationChromeModifier())
    }
}
