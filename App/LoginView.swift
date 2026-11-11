import SwiftUI
import UIKit

/// Вход: почта → код из письма (/api/auth/code + /api/auth/verify) или почта + пароль (/api/auth/login).
struct LoginView: View {
    @Environment(Store.self) private var store
    @State private var email = UserDefaults.standard.string(forKey: "lastEmail") ?? ""
    @State private var password = ""
    @State private var code = ""
    @State private var step = 0 // 0 — почта, 1 — код
    @State private var passMode = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?
    enum Field { case email, pass, code }

    var body: some View {
        ZStack {
            WallpaperView(wall: store.wall)
            if step == 0 {
                emailStep.transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                codeStep.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: passMode)
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("code") { email = "hi@disify.dev"; step = 1 }
            #endif
        }
    }

    private var emailStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            Image("BrandIcon")
                .resizable()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 25, y: 18)
            Text("Sguardo")
                .font(Typo.display(34))
                .tracking(-1)
                .foregroundStyle(Pal.fg)
                .padding(.top, 24)
            Text("Все переписки с клиентами — в одном месте")
                .font(Typo.body(16))
                .foregroundStyle(Pal.fg2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 10)
            Spacer()
            VStack(spacing: 12) {
                field(icon: "envelope", placeholder: String(localized: "Почта"), text: $email, secure: false)
                    .focused($focus, equals: .email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .submitLabel(passMode ? .next : .go)
                    .onSubmit { if passMode { focus = .pass } else { submit() } }
                if passMode {
                    field(icon: "lock", placeholder: String(localized: "Пароль"), text: $password, secure: true)
                        .focused($focus, equals: .pass)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let error {
                    Text(error).font(Typo.body(14)).foregroundStyle(Pal.danger).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                        .transition(.opacity)
                }
                Button(action: submit) {
                    ZStack {
                        if busy { ProgressView().tint(Pal.ink) } else { Text(passMode ? String(localized: "Войти") : String(localized: "Получить код")).font(Typo.body(17, .semibold)) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .primaryFill()
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityIdentifier("login-submit")
                Button {
                    passMode.toggle(); error = nil; haptic()
                } label: {
                    Text(passMode ? String(localized: "Войти по коду из письма") : String(localized: "Войти по паролю"))
                        .font(Typo.body(15, .medium)).foregroundStyle(Pal.acc).frame(height: 40)
                }
            }
            .padding(16)
            .glassRect(30)
            Text("Кабинет создаётся в веб-версии Sguardo.\nВход — той же почтой, что на disify.dev/sguardo.")
                .font(Typo.body(13))
                .foregroundStyle(Pal.fg3)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            CircleButton(system: "chevron.left", iconSize: 18) { step = 0; code = ""; error = nil }
                .padding(.top, 8)
            Text("Код из письма")
                .font(Typo.display(28))
                .tracking(-0.8)
                .foregroundStyle(Pal.fg)
                .padding(.top, 28)
            Text("Отправили 6 цифр на \(Text(email).foregroundColor(Pal.fg).font(Typo.body(16, .medium))). Письмо может идти до минуты.")
                .font(Typo.body(16))
                .foregroundStyle(Pal.fg2)
                .lineSpacing(4)
                .padding(.top, 12)
            ZStack {
                HStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in
                        let chars = Array(code)
                        Text(i < chars.count ? String(chars[i]) : "")
                            .font(Typo.display(24))
                            .foregroundStyle(Pal.fg)
                            .frame(width: 48, height: 60)
                            .glass(.light, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Pal.acc.opacity(i == min(code.count, 5) && focus == .code ? 0.7 : 0), lineWidth: 2))
                            .scaleEffect(i < chars.count ? 1 : 0.97)
                            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: chars.count)
                        if i < 5 { Spacer(minLength: 4) }
                    }
                }
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focus, equals: .code)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0.02)
                    .accessibilityIdentifier("code-field")
                    .onChange(of: code) { _, v in
                        let digits = String(v.filter(\.isNumber).prefix(6))
                        if digits != v { code = digits }
                        if digits.count == 6 { verify() }
                    }
            }
            .frame(height: 60)
            .padding(.top, 30)
            .contentShape(Rectangle())
            .onTapGesture { focus = .code }
            if let error {
                Text(error).font(Typo.body(14)).foregroundStyle(Pal.danger).padding(.top, 14)
            }
            Button {
                if let s = UIPasteboard.general.string {
                    code = String(s.filter(\.isNumber).prefix(6))
                }
            } label: {
                ZStack {
                    if busy { ProgressView().tint(Pal.fg) } else { Text("Вставить код из письма").font(Typo.body(15, .semibold)) }
                }
                .foregroundStyle(Pal.fg)
                .frame(maxWidth: .infinity).frame(height: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .glass(.light, in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
            .padding(.top, 28)
            Button { requestCode(resend: true) } label: {
                Text("Отправить код ещё раз").font(Typo.body(15, .medium)).foregroundStyle(Pal.acc).frame(maxWidth: .infinity).frame(height: 44)
            }
            .padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 16)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .code } }
    }

    @ViewBuilder
    private func field(icon: String, placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Pal.fg.opacity(0.75)).frame(width: 22)
            Group {
                if secure {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Pal.fg3))
                } else {
                    TextField("", text: text, prompt: Text(placeholder).foregroundColor(Pal.fg3))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(Typo.body(17))
            .foregroundStyle(Pal.fg)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .glass(.light, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var cleanEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private func submit() {
        guard !busy else { return }
        guard cleanEmail.contains("@"), cleanEmail.contains(".") else { withAnimation { error = String(localized: "Впиши почту") }; return }
        UserDefaults.standard.set(cleanEmail, forKey: "lastEmail")
        if passMode {
            guard !password.isEmpty else { withAnimation { error = String(localized: "Впиши пароль") }; return }
            busy = true; error = nil
            Task {
                defer { busy = false }
                do {
                    _ = try await API.send("POST", "/api/auth/login/", json: ["email": cleanEmail, "password": password])
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    await store.didLogin()
                } catch {
                    withAnimation { self.error = friendly(error) }
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        } else {
            requestCode(resend: false)
        }
    }

    private func requestCode(resend: Bool) {
        guard !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                _ = try await API.send("POST", "/api/auth/code/", json: ["email": cleanEmail])
                if resend { store.show(String(localized: "Новый код отправлен")) }
                withAnimation { step = 1 }
            } catch {
                withAnimation { self.error = friendly(error) }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func verify() {
        guard !busy, code.count == 6 else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                _ = try await API.send("POST", "/api/auth/verify/", json: ["email": cleanEmail, "code": code, "mode": "login"])
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                focus = nil
                await store.didLogin()
            } catch {
                withAnimation { self.error = friendly(error) }
                code = ""
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
