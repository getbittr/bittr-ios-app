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
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), eurValue: "N/A", chfValue: "N/A", currency: "€", weekPrices: [])
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration, eurValue: "94.250", chfValue: "94.250", currency: "€", weekPrices: sampleWeekPrices)
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
                    currency: preferredCurrency,
                    weekPrices: (mostRecentDownload["weekPrices"] as? [Double])?.map { CGFloat($0) } ?? []
                )
            } else {
                // No cache is available.
                return SimpleEntry (
                    date: currentDate,
                    configuration: configuration,
                    eurValue: "N/A",
                    chfValue: "N/A",
                    currency: "€",
                    weekPrices: []
                )
            }
        }()
        
        var newDataWasFetched = false
        
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
                
                #if DEBUG
                print("EUR value: \(formattedEurValue), CHF value: \(formattedChfValue), currency: \(preferredCurrency)")
                #endif
                
                // The week's history, for the medium widget's chart. Best
                // effort: on failure the previous series is kept rather than
                // blanking the chart.
                let rawCurrentValue = preferredCurrency == "CHF" ? actualChfValue : actualEurValue
                var weekPrices = await fetchWeekPrices(currency: preferredCurrency)
                if !weekPrices.isEmpty, let currentValue = Double(rawCurrentValue) {
                    // Finish on the value shown beside it, as the app's graph does.
                    weekPrices += [CGFloat(currentValue)]
                } else {
                    weekPrices = entry.weekPrices
                }
                
                // Cache latest data.
                let cacheDict:NSDictionary = [
                    "date": dateFormatter.string(from: currentDate),
                    "formattedEurValue":formattedEurValue,
                    "formattedChfValue":formattedChfValue,
                    "preferredCurrency":preferredCurrency,
                    "weekPrices":weekPrices.map { Double($0) }
                ]
                UserDefaults.standard.setValue(cacheDict, forKey: "mostrecentwidgetdata")
                
                newDataWasFetched = true
                
                entry = SimpleEntry(
                    date: currentDate,
                    configuration: configuration,
                    eurValue: formattedEurValue,
                    chfValue: formattedChfValue,
                    currency: preferredCurrency,
                    weekPrices: weekPrices
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

// The past week of daily prices, the same series the app's week graph plots.
func fetchWeekPrices(currency:String) async -> [CGFloat] {
    
    let pair = currency == "CHF" ? "chf" : "eur"
    
    guard
        let url = URL(string: "https://getbittr.com/api/price/btc/historical/\(pair)"),
        let (data, _) = try? await URLSession.shared.data(from: url),
        let json = try? JSONSerialization.jsonObject(with: data) as? [NSDictionary],
        json.count > 2,
        // [2] is the daily series; see ValueViewController for the full payload.
        let rawPoints = json[2]["data"] as? [NSDictionary]
    else { return [] }
    
    let formatter = ISO8601DateFormatter()
    let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    
    var prices = [CGFloat]()
    for eachPoint in rawPoints {
        guard
            let iso = eachPoint["time_iso8601"] as? String,
            let date = formatter.date(from: iso),
            cutoff < date,
            let priceString = eachPoint["price"] as? String,
            let price = Double(priceString)
        else { continue }
        prices += [CGFloat(price)]
    }
    
    // Drop the API's copy of the latest price.
    if !prices.isEmpty { prices.removeLast() }
    
    return prices
}

// Stand-in series for the gallery snapshot and the previews.
let sampleWeekPrices:[CGFloat] = [92100, 92800, 91400, 93600, 95200, 94100, 96800]

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
    let weekPrices: [CGFloat]
}

struct BittrWidgetEntryView : View {
    var entry: Provider.Entry
    
    @Environment(\.widgetFamily) private var family
    
    // Computed property for displayed value
    private var displayedValue: String {
        entry.currency == "CHF" ? entry.chfValue : entry.eurValue
    }
    
    // Change across the week's series, nil until it has loaded.
    private var weekChange: CGFloat? {
        guard let first = entry.weekPrices.first, let last = entry.weekPrices.last, first > 0 else { return nil }
        return (last - first) / first * 100
    }
    
    // The Value screen's profit view: 26pt tall, hugging its label, 13pt corner
    // radius, arrow and colours following gain or loss.
    @ViewBuilder private var profitView: some View {
        if let weekChange = self.weekChange {
            
            let percentage = "\(Int(weekChange)) %"
            let isLoss = percentage.contains("-")
            let tint = isLoss ? Color("LossText") : Color("ProfitText")
            
            HStack(spacing: 5) {
                // Rendered at its natural metrics, not .resizable(): resizing
                // an SF Symbol stretches the glyph into the frame and drops the
                // padding UIImageView keeps, which draws it noticeably larger.
                // 10.5pt matches the 11x11.65 the app's 11x16 aspect-fit box draws.
                Image(systemName: isLoss ? "arrow.down" : "arrow.up")
                    .font(.system(size: 10.5, weight: .regular))
                    .frame(width: 11, height: 16)
                    .foregroundColor(tint)
                
                Text(percentage)
                    .font(.custom("Gilroy-Regular", size: 14))
                    .foregroundColor(tint)
                    .lineLimit(1)
                    // The label sits a point below centre, as it does in the app.
                    .offset(y: 1)
            }
            .padding(.horizontal, 13)
            .frame(height: 26)
            .background(isLoss ? Color("LossBackground") : Color("ProfitBackground"))
            .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }
    
    // Shared by both sizes: small centres it, medium puts it top left.
    private var header: some View {
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
    }

    var body: some View {
        ZStack {
            ContainerRelativeShape().fill(Color("YellowOrDark2"))
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .padding(-20)
        .widgetURL(URL(string: "widget-deeplink://"))
    }
    
    private var smallLayout: some View {
        VStack {
            header
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
    
    // Header and chart down the left half, the value centred in the right. The
    // currency sits in the corner rather than under the value, so the value
    // centres on the widget instead of on the pair of them.
    private var mediumLayout: some View {
        ZStack {
            HStack(spacing: 14) {
                
                VStack(alignment: .leading, spacing: 0) {
                    // Lines the header up with the chart's leading edge below it.
                    header
                        .padding(.leading, 5)
                    
                    GraphLine(values: entry.weekPrices)
                        .stroke(Color("WhiteOrYellow"), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Keeps the curve off the widget's leading and bottom edges.
                        .padding(EdgeInsets(top: 10, leading: 5, bottom: 10, trailing: 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 8) {
                    // 36 renders at the size the small widget's 42 shrinks to:
                    // its column is wide enough that this never scales, where
                    // the small layout's box always trims a few points off.
                    Text("\(entry.currency) \(displayedValue)")
                        .font(.custom("Gilroy-Bold", size: 36))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundColor(Color("BlackOrWhite"))
                    
                    profitView
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            
            // Same corner placement as the small widget.
            Text("\(entry.currency)")
                .font(.custom("Gilroy-Bold", size: 18))
                .fontWeight(.bold)
                .foregroundColor(Color("WhiteOrYellow"))
                .padding(.trailing, 23)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    BittrWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "100.000", chfValue: "101.000", currency: "€", weekPrices: sampleWeekPrices)
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "90.000", chfValue: "91.000", currency: "CHF", weekPrices: sampleWeekPrices)
}

#Preview(as: .systemMedium) {
    BittrWidget()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "100.000", chfValue: "101.000", currency: "€", weekPrices: sampleWeekPrices)
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), eurValue: "90.000", chfValue: "91.000", currency: "CHF", weekPrices: sampleWeekPrices)
}
