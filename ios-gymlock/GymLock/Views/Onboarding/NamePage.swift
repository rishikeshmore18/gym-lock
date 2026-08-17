import Combine
import SwiftUI
import UIKit

/// Page 2 — "hi." lands alone, slides up, and the name question arrives.
/// The CTA communicates readiness through colour saturation only.
struct NamePage: View {
    let isActive: Bool
    @Binding var name: String
    @Binding var isEditing: Bool
    let onContinue: () -> Void

    @FocusState private var isFieldFocused: Bool
    @State private var questionShown = false
    @State private var keyboardHeight: CGFloat = 0

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool { !trimmedName.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if questionShown {
                Spacer().frame(height: 12)
            } else {
                Spacer()
            }

            Text("hi.")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: questionShown ? .leading : .center)

            if questionShown {
                Text("what should we call you?")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 18)

                nameField
                    .padding(.top, 22)

                Text("we'll keep it on this phone. nowhere else.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.top, 12)
            }

            Spacer()

            if questionShown {
                Button {
                    guard canContinue else { return }
                    isFieldFocused = false
                    Haptics.tap()
                    onContinue()
                } label: {
                    Text("Continue")
                }
                .buttonStyle(PrimaryCTAStyle(isEnabled: canContinue))
                .disabled(!canContinue)
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 16 : 40)
            }
        }
        .padding(.horizontal, Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.settle, value: questionShown)
        .animation(.easeOut(duration: 0.26), value: keyboardHeight)
        .onChange(of: isFieldFocused) { _, focused in
            isEditing = focused
        }
        .onReceive(keyboardHeightPublisher) { height in
            keyboardHeight = height
        }
        .task(id: isActive) {
            guard isActive else { return }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(Theme.settle) { questionShown = true }
        }
    }

    private var nameField: some View {
        TextField("", text: $name, prompt: placeholder)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Theme.ink)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isFieldFocused)
            .onSubmit {
                guard canContinue else { return }
                isFieldFocused = false
                onContinue()
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(
                        isFieldFocused ? Theme.accent : Theme.border,
                        lineWidth: isFieldFocused ? 2 : 1
                    )
            }
            .animation(Theme.stateChange, value: isFieldFocused)
            .accessibilityLabel("Your name")
    }

    private var placeholder: Text {
        Text("enter your name")
            .font(.system(size: 19, weight: .regular))
            .foregroundColor(Theme.inkTertiary)
    }

    /// Emits the on-screen keyboard height so the field and CTA stay above it.
    private var keyboardHeightPublisher: AnyPublisher<CGFloat, Never> {
        let willChange = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .map { notification -> CGFloat in
                guard
                    let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                    let screen = notification.object as? UIScreen ?? UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.screen }).first
                else { return 0 }
                return max(0, screen.bounds.height - frame.origin.y)
            }

        let willHide = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }

        return willChange.merge(with: willHide).eraseToAnyPublisher()
    }
}
