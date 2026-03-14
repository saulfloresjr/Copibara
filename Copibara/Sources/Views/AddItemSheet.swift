import SwiftUI

struct AddItemSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (String) -> Void

    @State private var content = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.base) {
            Text("Add Item")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.appTextPrimary)

            TextEditor(text: $content)
                .font(.system(size: 13))
                .frame(height: 120)
                .padding(4)
                .background(Color.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.appBorder, lineWidth: 1)
                )
                .focused($isFocused)

            HStack(spacing: Spacing.sm) {
                Button("Cancel") {
                    isPresented = false
                }

                Button("Add") {
                    add()
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 350)
        .onAppear {
            isFocused = true
        }
    }

    private func add() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        isPresented = false
    }
}
