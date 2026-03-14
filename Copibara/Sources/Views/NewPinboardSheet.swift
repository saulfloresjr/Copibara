import SwiftUI

struct NewPinboardSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String, String) -> Void  // (name, icon)

    @State private var name = ""
    @State private var selectedIcon = "📌"
    @FocusState private var isFocused: Bool

    private let icons = [
        "📌", "📋", "⭐️", "🔥", "💡", "🎨", "🎯", "🚀",
        "💻", "📝", "📎", "🔗", "🗂️", "📦", "🛠️", "🏷️",
        "💬", "📸", "🎵", "📐", "🧪", "🌐", "❤️", "⚡️"
    ]

    var body: some View {
        VStack(spacing: Spacing.base) {
            Text("New Pinboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.appTextPrimary)

            // Icon picker
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Icon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.appTextTertiary)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8), spacing: 4) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            Text(icon)
                                .font(.system(size: 16))
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedIcon == icon ? Color.appPrimary.opacity(0.3) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedIcon == icon ? Color.appPrimary : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("Enter name…", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { create() }

            HStack(spacing: Spacing.sm) {
                Button("Cancel") {
                    isPresented = false
                }

                Button("Create") {
                    create()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 300)
        .onAppear {
            isFocused = true
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed, selectedIcon)
        isPresented = false
    }
}
