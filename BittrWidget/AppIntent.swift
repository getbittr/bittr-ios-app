//
//  AppIntent.swift
//  BittrWidget
//
//  Created by Tom Melters on 17/12/2024.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Bitcoin Widget Configuration" }
    static var description: IntentDescription { "Configure your Bitcoin widget." }
}
