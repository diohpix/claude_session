import SwiftUI

/// 열린 tterm 세션의 대화 화면 아래 입력창. 보내면 tterm 제어 소켓으로 그 터미널에 입력한다.
/// Return은 보내기, Option+Return은 줄바꿈.
struct MessageComposer: View {
    let tty: String

    @State private var text = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("메시지를 입력하면 tterm의 이 세션으로 보냅니다", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                Button(action: send) {
                    if sending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!canSend)
                .help("보내기 (Return) · 줄바꿈은 Option+Return")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func send() {
        guard canSend else { return }
        let message = text
        sending = true
        errorMessage = nil
        Task {
            do {
                try await TtermControl.sendInput(tty: tty, text: message, submit: true)
                // 보내는 사이에 새로 입력한 내용은 지우지 않는다
                if text == message { text = "" }
            } catch {
                errorMessage = error.localizedDescription
            }
            sending = false
            focused = true
        }
    }
}
