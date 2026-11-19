import SwiftUI

/// The source, level, category and time menus. Search lives in the toolbar so Command-F reaches it.
struct LogFilterBar: View {
    @Bindable var logs: LogsModel

    private enum TimeChoice: Hashable {
        case live, last5Minutes, lastHour, last24Hours, custom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { menus }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        sourceMenu
                        levelMenu
                    }
                    HStack(spacing: 12) {
                        categoryMenu
                        timeMenu
                        resetButton
                    }
                }
            }
            if case .custom(let since, let until) = logs.filter.time {
                customRange(since: since, until: until)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var menus: some View {
        sourceMenu
        levelMenu
        categoryMenu
        timeMenu
        Spacer(minLength: 0)
        resetButton
    }

    private var sourceMenu: some View {
        Picker("Source", selection: $logs.filter.source) {
            Text(LogSourceFilter.all.title).tag(LogSourceFilter.all)
            Text(LogSourceFilter.host.title).tag(LogSourceFilter.host)
            Text(LogSourceFilter.android.title).tag(LogSourceFilter.android)
            Text(LogSourceFilter.web.title).tag(LogSourceFilter.web)
            ForEach(otherSources, id: \.self) { Text($0).tag(LogSourceFilter.other($0)) }
        }
        .menuPicker("Source")
    }

    // A saved filter can name a source that no longer exists, and a picker needs its current value as a tag.
    private var otherSources: [String] {
        var sources = logs.otherSources
        if case .other(let name) = logs.filter.source, !sources.contains(name) { sources.append(name) }
        return sources
    }

    private var levelMenu: some View {
        Picker("Level", selection: $logs.filter.minimumLevel) {
            ForEach(HostLogLevel.allCases, id: \.self) { Text($0.minimumTitle).tag($0) }
        }
        .menuPicker("Level")
    }

    private var categoryMenu: some View {
        Picker("Category", selection: $logs.filter.category) {
            Text("All categories").tag(String?.none)
            ForEach(categories, id: \.self) { Text($0).tag(String?.some($0)) }
        }
        .menuPicker("Category")
    }

    private var categories: [String] {
        var values = logs.categories
        if let name = logs.filter.category, !values.contains(name) { values.append(name) }
        return values
    }

    private var timeMenu: some View {
        Picker("Time", selection: timeChoice) {
            Text(LogTimeRange.live.title).tag(TimeChoice.live)
            Text(LogTimeRange.last5Minutes.title).tag(TimeChoice.last5Minutes)
            Text(LogTimeRange.lastHour.title).tag(TimeChoice.lastHour)
            Text(LogTimeRange.last24Hours.title).tag(TimeChoice.last24Hours)
            Divider()
            Text("Since…").tag(TimeChoice.custom)
        }
        .menuPicker("Time range")
    }

    @ViewBuilder private var resetButton: some View {
        if !logs.filter.isDefault {
            Button("Reset Filters") { logs.resetFilter() }
                .buttonStyle(.link)
        }
    }

    private var timeChoice: Binding<TimeChoice> {
        Binding(
            get: {
                switch logs.filter.time {
                case .live: .live
                case .last5Minutes: .last5Minutes
                case .lastHour: .lastHour
                case .last24Hours: .last24Hours
                case .custom: .custom
                }
            },
            set: { choice in
                switch choice {
                case .live: logs.filter.time = .live
                case .last5Minutes: logs.filter.time = .last5Minutes
                case .lastHour: logs.filter.time = .lastHour
                case .last24Hours: logs.filter.time = .last24Hours
                case .custom: logs.filter.time = .custom(since: Date().addingTimeInterval(-3_600), until: nil)
                }
            })
    }

    private func customRange(since: Date, until: Date?) -> some View {
        HStack(spacing: 12) {
            DatePicker(
                "Since",
                selection: Binding(
                    get: { since }, set: { logs.filter.time = .custom(since: $0, until: until) }),
                in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            Toggle(
                "Until",
                isOn: Binding(
                    get: { until != nil },
                    set: { logs.filter.time = .custom(since: since, until: $0 ? Date() : nil) }))
            if let until {
                DatePicker(
                    "Until",
                    selection: Binding(
                        get: { until }, set: { logs.filter.time = .custom(since: since, until: $0) }),
                    in: since..., displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
            }
        }
        .fixedSize()
    }
}

extension View {
    fileprivate func menuPicker(_ label: String) -> some View {
        pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(label)
    }
}
