import SwiftUI

struct DictionaryLookupView: View {
    let result: DictionaryLookupResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.term).font(.system(size: 24, weight: .medium, design: .serif))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text(result.source.rawValue.uppercased())
                .font(.caption.weight(.semibold)).tracking(1.1).foregroundStyle(.secondary)
            ScrollView {
                Text(result.definition)
                    .font(.system(size: 15, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(26)
        .frame(width: 480, height: 330)
        .background(paper)
    }
}
