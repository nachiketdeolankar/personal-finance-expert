import SwiftUI

struct CurrencyPickerView: View {
    @Binding var selectedCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""

    var filtered: [Currency] {
        search.isEmpty ? Currency.all :
        Currency.all.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.code.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { currency in
                Button {
                    selectedCode = currency.code
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currency.name).foregroundStyle(.primary)
                            Text(currency.code).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(currency.symbol)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        if selectedCode == currency.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .font(.footnote.bold())
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Search currencies")
            .navigationTitle("Currency")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}
