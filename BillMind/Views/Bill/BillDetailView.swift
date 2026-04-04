import SwiftUI

struct BillDetailView: View {
    let bill: BillRecord
    let currencySymbol: String
    @State private var showFullImage = false

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
                    DetailRow(label: "Category", value: "\(bill.category.englishName) (\(bill.category.displayName))")
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
        }
        .fullScreenCover(isPresented: $showFullImage) {
            if let image = billImage {
                ZoomableImageView(image: image)
            }
        }
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
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
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(20)
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
