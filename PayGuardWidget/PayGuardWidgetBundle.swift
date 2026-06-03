//
//  PayGuardWidgetBundle.swift
//  PayGuardWidget
//
//  Created by Ali Ozkul on 02.05.26.
//

import SwiftUI
import WidgetKit

@main
struct PayGuardWidgetBundle: WidgetBundle {
    var body: some Widget {
        PayGuardOverviewWidget()
        PayGuardFocusWidget()
    }
}
