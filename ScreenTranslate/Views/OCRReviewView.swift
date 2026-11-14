import SwiftUI
import ImageIO

struct OCRReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [OCRReviewItem]
    let imageData: Data
    let apply: ([Int: String]) -> Void
    @State private var drafts: [Int: String] = [:]
    @State private var confirmed = Set<Int>()
    @State private var crops: [Int: Data] = [:]
    @FocusState private var editing: Int?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("对照原图修改文字，或确认识别无误。只应用已确认的项目，其余继续保留提醒。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Section {
                        if let data = crops[item.id], let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 260)
                                .accessibilityLabel("待复核文字的原图区域")
                        }
                        TextField("核对文字", text: Binding(get: { drafts[item.id] ?? item.text }, set: {
                            drafts[item.id] = $0; confirmed.remove(item.id)
                        }), axis: .vertical).lineLimit(2...12).focused($editing, equals: item.id)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("reviewText-\(item.id)")
                        if !item.alternatives.isEmpty {
                            Menu("其他识字候选") {
                                ForEach(item.alternatives, id: \.self) { alternative in
                                    Button(alternative) { drafts[item.id] = alternative; confirmed.remove(item.id) }
                                }
                            }
                        }
                        Toggle("已对照原图确认", isOn: Binding(get: { confirmed.contains(item.id) }, set: {
                            if $0 { confirmed.insert(item.id) } else { confirmed.remove(item.id) }
                        })).disabled((drafts[item.id] ?? item.text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("confirmReview-\(item.id)")
                    } header: { Text(item.reasons.joined(separator: " · ")).sectionTitle() }
                }
            }.groupedListSpacing().navigationTitle("复核不确定文字").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("应用 \(confirmed.count) 项") {
                            apply(Dictionary(uniqueKeysWithValues: items.filter { confirmed.contains($0.id) }.map { ($0.id, drafts[$0.id] ?? $0.text) }))
                            dismiss()
                        }.disabled(confirmed.isEmpty).accessibilityIdentifier("applyOCRReview")
                    }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = nil } }
                }
                .task {
                    crops = await Task.detached(priority: .userInitiated) { Self.makeCrops(imageData, items: items) }.value
                }
        }
    }

    nonisolated private static func makeCrops(_ data: Data, items: [OCRReviewItem]) -> [Int: Data] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { return [:] }
        let w = Double(image.width), h = Double(image.height)
        var output: [Int: Data] = [:]
        for item in items {
            let box = item.box
            let rect = CGRect(x: box.x * w, y: (1 - box.y - box.height) * h, width: box.width * w, height: box.height * h)
                .insetBy(dx: -10, dy: -10).intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
            if let crop = image.cropping(to: rect) { output[item.id] = UIImage(cgImage: crop).pngData() }
        }
        return output
    }
}
