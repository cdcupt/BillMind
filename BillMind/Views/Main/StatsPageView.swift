import SwiftUI
import SwiftData
import Charts

struct StatsPageView: View {
    @Query(sort: \Journal.createdDate, order: .reverse) private var journals: [Journal]
    @State private var selectedJournalId: UUID?

    private var selectedJournal: Journal? {
        guard let id = selectedJournalId else { return nil }
        return journals.first(where: { $0.id == id })
    }

    private var filteredBills: [BillRecord] {
        if let journal = selectedJournal {
            return journal.bills
        }
        return journals.flatMap(\.bills)
    }

    private var allBills: [BillRecord] {
        filteredBills
    }

    private var totalAmount: Decimal {
        allBills.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var thisMonthBills: [BillRecord] {
        let calendar = Calendar.current
        let now = Date()
        return allBills.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
    }

    private var thisMonthTotal: Decimal {
        thisMonthBills.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var categoryData: [(category: BillCategory, total: Decimal)] {
        var totals: [BillCategory: Decimal] = [:]
        for bill in allBills {
            totals[bill.category, default: 0] += bill.amount
        }
        return totals.sorted { $0.value > $1.value }
            .map { (category: $0.key, total: $0.value) }
    }

    private var dailyData: [(date: Date, total: Decimal)] {
        let calendar = Calendar.current
        var totals: [Date: Decimal] = [:]
        for bill in thisMonthBills {
            let day = calendar.startOfDay(for: bill.date)
            totals[day, default: 0] += bill.amount
        }
        return totals.sorted { $0.key < $1.key }
            .map { (date: $0.key, total: $0.value) }
    }

    private var monthlyData: [(month: String, total: Decimal)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        var totals: [String: Decimal] = [:]
        var order: [String] = []
        let calendar = Calendar.current
        for bill in allBills {
            let month = formatter.string(from: bill.date)
            if totals[month] == nil { order.append(month) }
            totals[month, default: 0] += bill.amount
        }
        return order.map { (month: $0, total: totals[$0] ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Journal filter
                    if journals.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip(label: "All Journals", isSelected: selectedJournalId == nil) {
                                    selectedJournalId = nil
                                }
                                ForEach(journals) { journal in
                                    FilterChip(
                                        label: journal.name,
                                        isSelected: selectedJournalId == journal.id
                                    ) {
                                        selectedJournalId = journal.id
                                    }
                                }
                            }
                        }
                    }

                    if allBills.isEmpty {
                        EmptyStateView(
                            animal: .bear,
                            title: "No data yet",
                            subtitle: "Add some bills to see your statistics"
                        )
                    } else {
                        overviewCard
                        if selectedJournalId == nil && journals.count > 1 {
                            journalExpensesCard
                        }
                        categoryChart
                        dailyChart
                        monthlyChart
                        topMerchantsCard
                    }
                }
                .padding()
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Statistics")
                            .font(SketchTheme.titleFont(24))
                            .foregroundStyle(SketchTheme.softBrown)
                        AnimalMascotView(animal: .bear, size: 28)
                    }
                }
            }
        }
    }

    // MARK: - Overview Card

    private var overviewCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Spending")
                        .font(SketchTheme.captionFont())
                        .foregroundStyle(SketchTheme.lightBrown)
                    Text(totalAmount.formattedCurrency)
                        .font(SketchTheme.amountFont(32))
                        .foregroundStyle(SketchTheme.softBrown)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("This Month")
                        .font(SketchTheme.captionFont())
                        .foregroundStyle(SketchTheme.lightBrown)
                    Text(thisMonthTotal.formattedCurrency)
                        .font(SketchTheme.headlineFont(22))
                        .foregroundStyle(SketchTheme.dustyRose)
                }
            }

            HStack(spacing: 12) {
                StatChipView(label: "Journals", value: "\(journals.count)", color: SketchTheme.softBlue)
                StatChipView(label: "Bills", value: "\(allBills.count)", color: SketchTheme.sageGreen)
                StatChipView(label: "Categories", value: "\(categoryData.count)", color: SketchTheme.warmOrange)
            }
        }
        .sketchCard()
    }

    // MARK: - Category Chart

    // MARK: - Journal Expenses Card

    private var journalExpensesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Expenses by Journal")
                .font(SketchTheme.headlineFont(18))
                .foregroundStyle(SketchTheme.softBrown)

            ForEach(journals.sorted(by: { $0.totalAmount > $1.totalAmount })) { journal in
                HStack(spacing: 10) {
                    Image(journal.coverAnimal.imageName)
                        .resizable().scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(journal.name)
                            .font(SketchTheme.headlineFont(14))
                            .foregroundStyle(SketchTheme.softBrown)
                        Text("\(journal.billCount) bills")
                            .font(SketchTheme.captionFont(11))
                            .foregroundStyle(SketchTheme.lightBrown)
                    }
                    Spacer()
                    let symbol = CurrencyInfo.popular.first(where: { $0.code == journal.currency })?.symbol ?? journal.currency
                    Text("\(symbol)\(journal.totalAmount.formattedCurrency)")
                        .font(SketchTheme.headlineFont(16))
                        .foregroundStyle(SketchTheme.dustyRose)
                }
                if journal.id != journals.last?.id {
                    Divider()
                }
            }
        }
        .sketchCard()
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Category")
                .font(SketchTheme.headlineFont(18))
                .foregroundStyle(SketchTheme.softBrown)

            if categoryData.isEmpty {
                Text("No data")
                    .font(SketchTheme.bodyFont(14))
                    .foregroundStyle(SketchTheme.lightBrown)
            } else {
                Chart(categoryData, id: \.category) { item in
                    BarMark(
                        x: .value("Amount", NSDecimalNumber(decimal: item.total).doubleValue),
                        y: .value("Category", item.category.englishName)
                    )
                    .foregroundStyle(item.category.color)
                    .cornerRadius(6)
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(SketchTheme.lightBrown.opacity(0.3))
                        AxisValueLabel()
                            .font(SketchTheme.captionFont(10))
                            .foregroundStyle(SketchTheme.lightBrown)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(SketchTheme.captionFont(11))
                            .foregroundStyle(SketchTheme.softBrown)
                    }
                }
                .frame(height: CGFloat(categoryData.count) * 40 + 20)

                // Legend with amounts
                ForEach(categoryData, id: \.category) { item in
                    HStack(spacing: 8) {
                        Image(item.category.icon)
                            .resizable().scaledToFill()
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(item.category.displayName)
                            .font(SketchTheme.captionFont(12))
                            .foregroundStyle(SketchTheme.softBrown)
                        Spacer()
                        Text(item.total.formattedCurrency)
                            .font(SketchTheme.captionFont(12))
                            .foregroundStyle(item.category.color)
                    }
                }
            }
        }
        .sketchCard()
    }

    // MARK: - Daily Chart

    private var dailyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily (This Month)")
                .font(SketchTheme.headlineFont(18))
                .foregroundStyle(SketchTheme.softBrown)

            if dailyData.isEmpty {
                Text("No data this month")
                    .font(SketchTheme.bodyFont(14))
                    .foregroundStyle(SketchTheme.lightBrown)
            } else {
                Chart(dailyData, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Amount", NSDecimalNumber(decimal: item.total).doubleValue)
                    )
                    .foregroundStyle(SketchTheme.dustyRose.opacity(0.7))
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(SketchTheme.lightBrown.opacity(0.3))
                        AxisValueLabel(format: .dateTime.day())
                            .font(SketchTheme.captionFont(10))
                            .foregroundStyle(SketchTheme.lightBrown)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(SketchTheme.captionFont(10))
                            .foregroundStyle(SketchTheme.lightBrown)
                    }
                }
                .frame(height: 180)
            }
        }
        .sketchCard()
    }

    // MARK: - Monthly Chart

    private var monthlyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Trend")
                .font(SketchTheme.headlineFont(18))
                .foregroundStyle(SketchTheme.softBrown)

            if monthlyData.count < 2 {
                Text("Need at least 2 months of data")
                    .font(SketchTheme.bodyFont(14))
                    .foregroundStyle(SketchTheme.lightBrown)
            } else {
                Chart(monthlyData, id: \.month) { item in
                    LineMark(
                        x: .value("Month", item.month),
                        y: .value("Amount", NSDecimalNumber(decimal: item.total).doubleValue)
                    )
                    .foregroundStyle(SketchTheme.softBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    PointMark(
                        x: .value("Month", item.month),
                        y: .value("Amount", NSDecimalNumber(decimal: item.total).doubleValue)
                    )
                    .foregroundStyle(SketchTheme.softBlue)
                    .symbolSize(40)

                    AreaMark(
                        x: .value("Month", item.month),
                        y: .value("Amount", NSDecimalNumber(decimal: item.total).doubleValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SketchTheme.softBlue.opacity(0.3), SketchTheme.softBlue.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(SketchTheme.captionFont(11))
                            .foregroundStyle(SketchTheme.softBrown)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(SketchTheme.captionFont(10))
                            .foregroundStyle(SketchTheme.lightBrown)
                    }
                }
                .frame(height: 200)
            }
        }
        .sketchCard()
    }

    // MARK: - Top Merchants

    private var topMerchantsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Merchants")
                .font(SketchTheme.headlineFont(18))
                .foregroundStyle(SketchTheme.softBrown)

            let merchants = topMerchants
            if merchants.isEmpty {
                Text("No merchant data")
                    .font(SketchTheme.bodyFont(14))
                    .foregroundStyle(SketchTheme.lightBrown)
            } else {
                ForEach(Array(merchants.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(SketchTheme.headlineFont(14))
                            .foregroundStyle(SketchTheme.lightBrown)
                            .frame(width: 20)
                        Text(item.name)
                            .font(SketchTheme.bodyFont(14))
                            .foregroundStyle(SketchTheme.softBrown)
                        Spacer()
                        Text("\(item.count) bills")
                            .font(SketchTheme.captionFont(11))
                            .foregroundStyle(SketchTheme.lightBrown)
                        Text(item.total.formattedCurrency)
                            .font(SketchTheme.headlineFont(14))
                            .foregroundStyle(SketchTheme.dustyRose)
                    }
                    if index < merchants.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .sketchCard()
    }

    private var topMerchants: [(name: String, count: Int, total: Decimal)] {
        var data: [String: (count: Int, total: Decimal)] = [:]
        for bill in allBills {
            let name = bill.merchant ?? bill.category.displayName
            let existing = data[name, default: (count: 0, total: 0)]
            data[name] = (count: existing.count + 1, total: existing.total + bill.amount)
        }
        return data.sorted { $0.value.total > $1.value.total }
            .prefix(5)
            .map { (name: $0.key, count: $0.value.count, total: $0.value.total) }
    }
}

// MARK: - Stat Chip

struct StatChipView: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(SketchTheme.headlineFont(20))
                .foregroundStyle(color)
            Text(label)
                .font(SketchTheme.captionFont(11))
                .foregroundStyle(SketchTheme.lightBrown)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SketchTheme.captionFont(13))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? SketchTheme.dustyRose.opacity(0.15) : SketchTheme.warmWhite)
                .foregroundStyle(isSelected ? SketchTheme.dustyRose : SketchTheme.softBrown)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? SketchTheme.dustyRose.opacity(0.4) : SketchTheme.lightBrown.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
