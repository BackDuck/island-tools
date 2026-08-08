import SwiftUI

struct NotesTabView: View {
    let notes: [NoteItem]
    var onAdd: (String) -> Void
    var onUpdate: (NoteItem, String) -> Void
    var onDelete: (NoteItem) -> Void

    @Environment(\.themePalette) private var palette
    @State private var draft = ""
    @State private var expandedID: UUID?
    @State private var editText = ""
    @State private var hoveredID: UUID?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(IslandTab.notes.title)
                .font(IslandTheme.headerFont)
                .tracking(1.2)
                .foregroundStyle(palette.tertiaryText)
                .padding(.leading, IslandTheme.contentHorizontalPadding)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(notes) { note in
                        noteRow(note)
                    }
                }
                .padding(.horizontal, IslandTheme.contentHorizontalPadding)
            }

            inputBar
                .padding(.horizontal, IslandTheme.contentHorizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // Сразу в поле ввода, как только открыли вкладку.
            DispatchQueue.main.async {
                inputFocused = true
            }
        }
    }

    private func noteRow(_ note: NoteItem) -> some View {
        let expanded = expandedID == note.id
        let hovered = hoveredID == note.id
        return VStack(alignment: .leading, spacing: 8) {
            if expanded {
                TextEditor(text: $editText)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(palette.primaryText)
                    .frame(minHeight: 56, maxHeight: 88)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.controlFill.opacity(0.8))
                    )
                    .onChange(of: editText) { _, newValue in
                        onUpdate(note, newValue)
                    }

                HStack {
                    Button {
                        expandedID = nil
                    } label: {
                        Text("Свернуть")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.tertiaryText)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                    deleteButton(note)
                }
            } else {
                HStack(spacing: 8) {
                    Text(note.text)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            expandedID = note.id
                            editText = note.text
                        }

                    if hovered {
                        deleteButton(note)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(expanded || hovered ? palette.rowHoverFill : palette.rowFill)
        )
        .onHover { inside in
            hoveredID = inside ? note.id : (hoveredID == note.id ? nil : hoveredID)
        }
    }

    private func deleteButton(_ note: NoteItem) -> some View {
        Button {
            onDelete(note)
            if expandedID == note.id {
                expandedID = nil
            }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(palette.controlFill))
        }
        .buttonStyle(.plain)
        .help("Удалить")
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.tertiaryText)

            TextField("Новая заметка…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(palette.primaryText)
                .focused($inputFocused)
                .onSubmit {
                    commitDraft()
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.rowFill)
        )
    }

    private func commitDraft() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onAdd(text)
        draft = ""
        // Enter сохранил — фокус остаётся в поле.
        inputFocused = true
    }
}
