//
//  BittrWidget.swift
//  BittrWidget
//
//  Created by Tom Melters on 17/12/2024.
//

import WidgetKit
import SwiftUI

struct Provider: AppIntentTimelineProvider {
    
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), eurValue: "N/A", chfValue: "N/A", currency: "€")
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration, eurValue: "94.250", chfValue: "94.250", currency: "€")
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        
        let currentDate = Date()
        var entry = SimpleEntry (
            date: currentDate,
            configuration: configuration,
            eurValue: "N/A",
            chfValue: "N/A",
            currency: "€"
        )
        
        do {
            let envUrl = URL(string: "https://getbittr.com/api/price/btc")!
            let (data, _) = try await URLSession.shared.data(from: envUrl)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let actualEurValue = json["btc_eur"] as? String, let actualChfValue = json["btc_chf"] as? String {
                // Create an entry with the fetched data
                
                let formattedEurValue = formatEuroValue(actualEurValue)
                let formattedChfValue = formatEuroValue(actualChfValue)
                
                var preferredCurrency = "€"
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                    preferredCurrency = "CHF"
                }
                
                print("EUR value: \(formattedEurValue), CHF value: \(formattedChfValue), currency: \(preferredCurrency)")
                
                entry = SimpleEntry(
                    date: currentDate,
                    configuration: configuration,
                    eurValue: formattedEurValue,
                    chfValue: formattedChfValue,
                    currency: preferredCurrency
                )
            }
        } catch {
            print("Error fetching data: \(error.localizedDescription)")
        }
        
        // Fetch fresh data in 4 hours.
        var timeInterval:Double = 14400
        if entry.eurValue == "N/A" {
            // Data couldn't be fetched. Try again in 30 minutes.
            timeInterval = 1800
        }
        
        return Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(timeInterval)))
    }
}

func formatEuroValue(_ actualEurValue: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal // Automatically adds separators
    formatter.maximumFractionDigits = 0 // Round to whole numbers
    formatter.locale = Locale.current // Use current locale for separators
    
    // Convert string to number and format it
    if let number = Double(actualEurValue) {
        return formatter.string(from: NSNumber(value: round(number))) ?? "0"
    } else {
        return "0" // Fallback in case of invalid input
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let eurValue: String
    let chfValue: String
    let currency: String
}

struct BittrWidgetEntryView : View {
    var entry: Provider.Entry
    
    // Computed property for displayed value
    private var displayedValue: String {
        entry.currency == "CHF" ? entry.chfValue : entry.eurValue
    }

    var body: some View {
        ZStack {
            ContainerRelativeShape().fill(Color(UIColor(displayP3Red: 246/255, green: 199/255, blue: 68/255, alpha: 1)))
            VStack {
                HStack {
                    Image("iconpiggywhite")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .padding(.trailing, 1)
                        .padding(.leading, -3)
                    Text("bitcoin value")
                        .font(.custom("Gilroy-Bold", size: 16))
                        .fontWeight(.bold)
                        .foregroundColor(Color.white.opacity(1))
                        .font(.title3)
                        .padding(.top, 3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 20)
                
                Spacer()
                
                Text("\(entry.currency) \(displayedValue)")
                    .font(.custom("Gilroy-Bold", size: 42))
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal)
                    .lineLimit(1)
                    .padding(.top, 6)
                    .padding(.leading, 3)
                    .padding(.trailing, 3)
                
                Spacer()
                
                HStack {
                    Spacer()
                    
                    Text("\(entry.currency)")
                        .font(.custom("Gilroy-Bold", size: 18))
                        .fontWeight(.bold)
                        .foregroundColor(Color.white.opacity(1))
                        .font(.title3)
                        .padding(.trailing, 23)
                        .padding(.bottom, 20)
                }
                
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(-20)
    }
}

struct BittrWidget: Widget {
    let kind: String = "BittrWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            BittrWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bittr bitcoin value")
        .description("See bitcoin's current value at a glance on your home screen.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    BittrWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "100.000", chfValue: "101.000", currency: "€")
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "90.000", chfValue: "91.000", currency: "CHF")
}
