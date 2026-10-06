import SwiftUI

struct ModelSelectionView: View {
    @Environment(\.appTheme) private var theme
    var provider: AIProvider
    var fetched: [String]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    var body: some View {
        NavigationStack {
            List {
                if !provider.models.isEmpty {
                    Section("常用模型") {
                        ForEach(provider.models.filter { matches($0.id + $0.title) }) { model in
                            Button { selection = model.id; dismiss() } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(model.title).foregroundStyle(.primary)
                                        Text(model.detail + " · " + model.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selection == model.id { Image(systemName: "checkmark").foregroundStyle(theme.accent) }
                                }.padding(.vertical, 4)
                            }.accessibilityIdentifier("model-" + model.id)
                        }
                    }
                }
                if !fetched.isEmpty {
                    Section("账户返回的模型") {
                        ForEach(fetched.filter(matches), id: \.self) { model in
                            Button { selection = model; dismiss() } label: {
                                HStack { Text(model); Spacer(); if selection == model { Image(systemName: "checkmark") } }
                            }.accessibilityIdentifier(model)
                        }
                    }
                }
                if provider.models.isEmpty && fetched.isEmpty {
                    Text("先获取模型列表，也可在 API 设置中手动填写模型 ID。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("选择模型").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索模型")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }
    }
}
