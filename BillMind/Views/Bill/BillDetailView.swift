import SwiftUI

struct BillDetailView: View {
    @Bindable var bill: BillRecord
    let currencySymbol: String
    @Environment(\.modelContext) private var modelContext
    @State private var showFullImage = false
    @State private var showEdit = false

    private var billImage: UIImage? {
        guard let path = bill.imagePaths.first else { return nil }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = dir.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Bill Image (tappable for zoom)
                if let image = billImage {
                    Button { showFullImage = true } label: {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: SketchTheme.paperShadow, radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                }

                // Header
                VStack(spacing: 8) {
                    Image(bill.category.icon)
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(bill.merchant ?? bill.category.displayName)
                        .font(SketchTheme.titleFont(24))
                        .foregroundStyle(SketchTheme.softBrown)
                    Text("\(currencySymbol)\(bill.amount.formattedCurrency)")
                        .font(SketchTheme.amountFont(42))
                        .foregroundStyle(bill.category.color)
                    StatusBadge(status: bill.status)
                }
                .frame(maxWidth: .infinity)
                .sketchCard()

                // Details
                VStack(spacing: 12) {
                    DetailRow(label: "Category", value: bill.category.englishName)
                    DetailRow(label: "Date", value: bill.date.formatted(as: "yyyy-MM-dd HH:mm"))
                    if let currency = bill.originalCurrency {
                        DetailRow(label: "Currency", value: currency)
                    }
                    if let note = bill.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Note")
                                .font(SketchTheme.captionFont())
                                .foregroundStyle(SketchTheme.lightBrown)
                            Text(note)
                                .font(SketchTheme.bodyFont(14))
                                .foregroundStyle(SketchTheme.softBrown)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let provider = bill.aiProvider {
                        DetailRow(label: "Recognized by", value: provider.displayName)
                    }
                }
                .sketchCard()

                // Line Items
                if !bill.lineItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Line Items")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        ForEach(bill.lineItems) { item in
                            HStack {
                                Text(item.itemDescription)
                                    .font(SketchTheme.bodyFont(14))
                                    .foregroundStyle(SketchTheme.softBrown)
                                if item.quantity > 1 {
                                    Text("×\(item.quantity)")
                                        .font(SketchTheme.captionFont(12))
                                        .foregroundStyle(SketchTheme.lightBrown)
                                }
                                Spacer()
                                Text("\(currencySymbol)\(item.amount.formatted2)")
                                    .font(SketchTheme.headlineFont(14))
                                    .foregroundStyle(SketchTheme.softBrown)
                            }
                            .padding(.vertical, 4)
                            if item.id != bill.lineItems.last?.id {
                                Divider()
                            }
                        }
                    }
                    .sketchCard()
                }
            }
            .padding()
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Bill Detail")
                    .font(SketchTheme.headlineFont(20))
                    .foregroundStyle(SketchTheme.softBrown)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(SketchTheme.dustyRose)
                }
            }
        }
        .fullScreenCover(isPresented: $showFullImage) {
            if let image = billImage {
                ZoomableImageView(image: image)
            }
        }
        .sheet(isPresented: $showEdit) {
            EditBillView(bill: bill)
        }
    }
}

// MARK: - Edit Bill View

struct EditBillView: View {
    @Bindable var bill: BillRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var merchant: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var selectedCategory: BillCategory = .misc
    @State private var currency: String = ""
    @State private var note: String = ""
    @State private var lineItems: [BillLineItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Amount
                    VStack(spacing: 4) {
                        Text("Amount")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        TextField("0.00", text: $amountText)
                            .font(SketchTheme.amountFont(42))
                            .foregroundStyle(SketchTheme.dustyRose)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .sketchCard()

                    // Merchant
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Merchant")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        TextField("Store or company name", text: $merchant)
                            .font(SketchTheme.bodyFont())
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(SketchTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .sketchCard()

                    // Category
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        LazyVGrid(columns: [
                            GridItem(.flexible()), GridItem(.flexible()),
                            GridItem(.flexible()), GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 10) {
                            ForEach(BillCategory.allCases) { category in
                                Button { selectedCategory = category } label: {
                                    VStack(spacing: 4) {
                                        Image(category.icon)
                                            .resizable().scaledToFill()
                                            .frame(width: 28, height: 28)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        Text(category.englishName)
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selectedCategory == category ? category.color.opacity(0.15) : SketchTheme.cream)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedCategory == category ? category.color.opacity(0.5) : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(SketchTheme.softBrown)
                            }
                        }
                    }
                    .sketchCard()

                    // Date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        DatePicker("", selection: $date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(SketchTheme.dustyRose)
                    }
                    .sketchCard()

                    // Note
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        TextField("Additional details...", text: $note, axis: .vertical)
                            .font(SketchTheme.bodyFont(14))
                            .textFieldStyle(.plain)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(SketchTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .sketchCard()

                    // Line Items
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Line Items")
                                .font(SketchTheme.captionFont())
                                .foregroundStyle(SketchTheme.lightBrown)
                            Spacer()
                            Button {
                                lineItems.append(BillLineItem(itemDescription: "", amount: 0))
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add")
                                        .font(SketchTheme.captionFont(12))
                                }
                                .foregroundStyle(SketchTheme.dustyRose)
                            }
                        }

                        if lineItems.isEmpty {
                            Text("No line items")
                                .font(SketchTheme.bodyFont(13))
                                .foregroundStyle(SketchTheme.lightBrown)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(lineItems.indices, id: \.self) { index in
                                HStack(spacing: 8) {
                                    TextField("Description", text: Binding(
                                        get: { lineItems[safe: index]?.itemDescription ?? "" },
                                        set: { if lineItems.indices.contains(index) { lineItems[index].itemDescription = $0 } }
                                    ))
                                    .font(SketchTheme.bodyFont(13))
                                    .textFieldStyle(.plain)

                                    TextField("0.00", text: Binding(
                                        get: { lineItems[safe: index].map { $0.amount.formatted2 } ?? "" },
                                        set: {
                                            if lineItems.indices.contains(index),
                                               let val = Decimal(string: $0) {
                                                lineItems[index].amount = val
                                            }
                                        }
                                    ))
                                    .font(SketchTheme.headlineFont(13))
                                    .foregroundStyle(SketchTheme.softBrown)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.plain)
                                    .frame(width: 70)
                                    .multilineTextAlignment(.trailing)

                                    Button {
                                        lineItems.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(SketchTheme.mutedRed.opacity(0.6))
                                            .font(.system(size: 18))
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(SketchTheme.cream)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .sketchCard()

                    // Save
                    Button { saveBill() } label: {
                        HStack {
                            Image(systemName: "checkmark")
                            Text("Save Changes")
                                .font(SketchTheme.headlineFont(18))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SketchTheme.primaryGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Edit Bill")
                        .font(SketchTheme.headlineFont(20))
                        .foregroundStyle(SketchTheme.softBrown)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SketchTheme.dustyRose)
                }
            }
            .onAppear { loadBill() }
        }
    }

    private func loadBill() {
        merchant = bill.merchant ?? ""
        amountText = bill.amount.formatted2
        date = bill.date
        selectedCategory = bill.category
        currency = bill.originalCurrency ?? ""
        note = bill.note ?? ""
        lineItems = bill.lineItems
    }

    private func saveBill() {
        if let amount = Decimal(string: amountText) {
            bill.amount = amount
        }
        bill.merchant = merchant.isEmpty ? nil : merchant
        bill.date = date
        bill.category = selectedCategory
        bill.originalCurrency = currency.isEmpty ? nil : currency
        bill.note = note.isEmpty ? nil : note
        bill.lineItems = lineItems.filter { !$0.itemDescription.isEmpty }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var showShareSheet = false
    @State private var savedMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Image area (scrollable for tall images, tappable to dismiss)
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = lastScale * value.magnification
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1 { withAnimation { scale = 1; lastScale = 1 } }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1 { scale = 1; lastScale = 1 }
                            else { scale = 2.5; lastScale = 2.5 }
                        }
                    }
                    .onTapGesture(count: 1) {
                        dismiss()
                    }
            }
            .background(Color.black)
            .overlay {
                // Toast
                if let msg = savedMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(.bottom, 20)
                    }
                }
            }

            // Bottom bar on black background (below image)
            HStack(spacing: 40) {
                Button {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    savedMessage = "Saved to Photos"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedMessage = nil }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 20))
                        Text("Save")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }

                Button { showShareSheet = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                        Text("Share")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .background(Color.black)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [image])
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(SketchTheme.captionFont())
                .foregroundStyle(SketchTheme.lightBrown)
            Spacer()
            Text(value)
                .font(SketchTheme.bodyFont(14))
                .foregroundStyle(SketchTheme.softBrown)
        }
    }
}
