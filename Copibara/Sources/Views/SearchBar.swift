import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.appTextTertiary)

            TextField("Search copibara history…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextTertiary)
                }
                .buttonStyle(.plain)
            }

            Text("⌘K")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.appBorder.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.appBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isFocused ? Color.appPrimary : Color.appBorder, lineWidth: 1)
        )
    }

    func focus() {
        isFocused = true
    }
}
