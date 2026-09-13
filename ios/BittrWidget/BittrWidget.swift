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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd MMM yyyy HH:mm"
        
        var entry:SimpleEntry = {
            if
                let mostRecentDownload = UserDefaults.standard.value(forKey: "mostrecentwidgetdata") as? NSDictionary,
                let date = mostRecentDownload["date"] as? String,
                let formattedEurValue = mostRecentDownload["formattedEurValue"] as? String,
                let formattedChfValue = mostRecentDownload["formattedChfValue"] as? String,
                let preferredCurrency = mostRecentDownload["preferredCurrency"] as? String {
                
                // Cache is available.
                return SimpleEntry (
                    date: dateFormatter.date(from: date) ?? currentDate,
                    configuration: configuration,
                    eurValue: formattedEurValue,
                    chfValue: formattedChfValue,
                    currency: preferredCurrency
                )
            } else {
                // No cache is available.
                return SimpleEntry (
                    date: currentDate,
                    configuration: configuration,
                    eurValue: "N/A",
                    chfValue: "N/A",
                    currency: "€"
                )
            }
        }()
        
        var newDataWasFetched = false
        
        do {
            let envUrl = URL(string: "\(BittrAPIEnvironment.baseURL)/price/btc")!
            let (data, _) = try await URLSession.shared.data(from: envUrl)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let actualEurValue = json["btc_eur"] as? String, let actualChfValue = json["btc_chf"] as? String {
                // Create an entry with the fetched data
                
                let formattedEurValue = formatEuroValue(actualEurValue)
                let formattedChfValue = formatEuroValue(actualChfValue)
                
                var preferredCurrency = "€"
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                    preferredCurrency = "CHF"
                }
                
                #if DEBUG
                print("EUR value: \(formattedEurValue), CHF value: \(formattedChfValue), currency: \(preferredCurrency)")
                #endif
                
                // Cache latest data.
                let cacheDict:NSDictionary = [
                    "date": dateFormatter.string(from: currentDate),
                    "formattedEurValue":formattedEurValue,
                    "formattedChfValue":formattedChfValue,
                    "preferredCurrency":preferredCurrency
                ]
                UserDefaults.standard.setValue(cacheDict, forKey: "mostrecentwidgetdata")
                
                newDataWasFetched = true
                
                entry = SimpleEntry(
                    date: currentDate,
                    configuration: configuration,
                    eurValue: formattedEurValue,
                    chfValue: formattedChfValue,
                    currency: preferredCurrency
                )
            }
        } catch {
            #if DEBUG
            print("Error fetching data: \(error.localizedDescription)")
            #endif
        }
        
        // Schedule next data download.
        let timeInterval:Double = {
            if newDataWasFetched {
                // Data was fetched. Fetch fresh data in 2 hours.
                return 7200
            } else {
                // Data couldn't be fetched. Try again in 30 minutes.
                return 1800
            }
        }()
        
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
            ContainerRelativeShape().fill(Color("YellowOrDark2"))
            VStack {
                HStack {
                    Image("iconpiggy")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .padding(.trailing, 1)
                        .padding(.leading, -3)
                    Text("bitcoin value")
                        .font(.custom("Gilroy-Bold", size: 16))
                        .fontWeight(.bold)
                        .foregroundColor(Color("WhiteOrYellow"))
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
                    .foregroundColor(Color("BlackOrWhite"))
                
                Spacer()
                
                HStack {
                    Spacer()
                    
                    Text("\(entry.currency)")
                        .font(.custom("Gilroy-Bold", size: 18))
                        .fontWeight(.bold)
                        .foregroundColor(Color("WhiteOrYellow"))
                        .font(.title3)
                        .padding(.trailing, 23)
                        .padding(.bottom, 20)
                }
                
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(-20)
        .widgetURL(URL(string: "widget-deeplink://"))
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

// The four states of shared/docs/widget-spec.md §3.2, in the order the capture runbook
// (shared/docs/widget-capture-runbook.md) refers to them. The preview harness takes these
// entries directly, so `N/A` needs no airplane mode and no cache clearing — scrub the
// canvas timeline and toggle the canvas appearance to get all four stills BIT-76 asks for.
#Preview(as: .systemSmall) {
    BittrWidget()
} timeline: {
    // 1 — populated, the spec's canonical price (also what `snapshot(for:in:)` hard-codes).
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "94.250", chfValue: "91.000", currency: "€")
    // 2 — widest realistic string: the CHF prefix is 3 glyphs, so this is the worst case
    //     for minimumScaleFactor(0.5). See §6.2.
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "100.000", chfValue: "100.000", currency: "CHF")
    // 3 — no cache and the fetch failed (§3.2 state 2), visually identical to placeholder().
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "N/A", chfValue: "N/A", currency: "€")
    // 4 — malformed payload: formatEuroValue's "0" fallback (§3.2 state 5). Looks like a
    //     real price rather than an error, which is the point of keeping it visible here.
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "0", chfValue: "0", currency: "€")
}
