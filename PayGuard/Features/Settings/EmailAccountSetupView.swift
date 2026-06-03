//
//  EmailAccountSetupView.swift
//  PayGuard
//

import SwiftData
import SwiftUI

struct EmailAccountSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var provider: EmailProviderKind = .gmail
    @State private var displayName = ""
    @State private var emailAddress = ""
    @State private var username = ""
    @State private var password = ""
    @State private var host = EmailProviderKind.gmail.defaultHost
    @State private var portText = String(EmailProviderKind.gmail.defaultPort)
    @State private var useTLS = true
    @State private var validationMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                PayGuardBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionTitleView(
                            eyebrow: "Connect Mailbox",
                            title: "Add an email account for automatic scanning.",
                            detail: "PayGuard uses IMAP access to scan mailbox history for subscriptions. Gmail, iCloud, Outlook, Yahoo, Proton Bridge, and other providers can be connected when IMAP access is enabled."
                        )

                        providerPanel
                        credentialsPanel
                        serverPanel
                        privacyPanel

                        if let validationMessage {
                            Text(validationMessage)
                                .font(PayGuardTheme.captionFont)
                                .foregroundStyle(PayGuardTheme.destructive)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            saveAccount()
                        } label: {
                            if isSaving {
                                HStack {
                                    ProgressView()
                                    Text("Testing and saving account…".localizedKey)
                                }
                            } else {
                                Label("Save email account", systemImage: "checkmark.shield.fill")
                            }
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .disabled(isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Connect Email")
            .navigationBarTitleDisplayMode(.inline)
            .payGuardNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        ToolbarCircleIcon(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onChange(of: provider) { _, newProvider in
                host = newProvider.defaultHost
                portText = String(newProvider.defaultPort)
                useTLS = newProvider != .proton
                if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayName = newProvider.label
                }
            }
            .onChange(of: emailAddress) { _, value in
                if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username == emailAddress {
                    username = value
                }
            }
        }
    }

    private var providerPanel: some View {
        PayGuardPanel(
            title: "Provider",
            symbol: provider.symbolName,
            detail: provider.requiresAppPasswordHint
        ) {
            Picker("Provider", selection: $provider) {
                ForEach(EmailProviderKind.allCases) { provider in
                    Label(provider.label, systemImage: provider.symbolName)
                        .tag(provider)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("PayGuard cannot silently read accounts already configured inside Apple Mail. Add the mailbox here so PayGuard can connect to the mail server and scan automatically.".localizedKey)
                .font(PayGuardTheme.captionFont)
                .foregroundStyle(PayGuardTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var credentialsPanel: some View {
        PayGuardPanel(
            title: "Login",
            symbol: "person.badge.key.fill",
            detail: "Use your email address and an app password when the provider requires it. The password is saved in the iOS Keychain."
        ) {
            premiumTextField("Display name", text: $displayName, systemName: "textformat")
            premiumTextField("Email address", text: $emailAddress, systemName: "envelope.fill", keyboard: .emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            premiumTextField("Username", text: $username, systemName: "person.fill", keyboard: .emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .foregroundStyle(PayGuardTheme.accent)
                    .frame(width: 24)
                SecureField("Password / app password".localizedKey, text: $password)
                    .font(.system(.body, design: .rounded))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PayGuardTheme.inputFill))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PayGuardTheme.stroke, lineWidth: 1)
            }
        }
    }

    private var serverPanel: some View {
        PayGuardPanel(
            title: "IMAP server",
            symbol: "server.rack",
            detail: "These defaults are prefilled for common providers. Change them only if your mail provider gives different IMAP settings."
        ) {
            premiumTextField("IMAP host", text: $host, systemName: "network")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            premiumTextField("Port", text: $portText, systemName: "number", keyboard: .numberPad)

            Toggle(isOn: $useTLS) {
                Label("Use TLS", systemImage: "lock.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(PayGuardTheme.textPrimary)
            }
            .tint(PayGuardTheme.accent)
        }
    }

    private var privacyPanel: some View {
        PayGuardPanel(
            title: "What PayGuard scans",
            symbol: "shield.lefthalf.filled",
            detail: "After connecting, PayGuard searches mailbox history for receipt, invoice, renewal, subscription, payment, billing, and cancellation signals. It creates suggestions, not saved subscriptions, until you approve them."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Credentials stay in the device Keychain.", systemImage: "checkmark.circle.fill")
                Label("Detected subscriptions are shown before saving.", systemImage: "checkmark.circle.fill")
                Label("You can delete the connected account anytime.", systemImage: "checkmark.circle.fill")
            }
            .font(PayGuardTheme.captionFont)
            .foregroundStyle(PayGuardTheme.textSecondary)
        }
    }

    private func premiumTextField(
        _ placeholder: String,
        text: Binding<String>,
        systemName: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .foregroundStyle(PayGuardTheme.accent)
                .frame(width: 24)
            TextField(placeholder.localizedKey, text: text)
                .keyboardType(keyboard)
                .font(.system(.body, design: .rounded))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PayGuardTheme.inputFill))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PayGuardTheme.stroke, lineWidth: 1)
        }
    }

    private func saveAccount() {
        let cleanEmail = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, cleanEmail.contains("@") else {
            validationMessage = PMLocalized("Enter a valid email address.")
            return
        }
        guard !cleanUsername.isEmpty else {
            validationMessage = PMLocalized("Enter the IMAP username.")
            return
        }
        guard !cleanPassword.isEmpty else {
            validationMessage = PMLocalized("Enter the email password or app password.")
            return
        }
        guard !cleanHost.isEmpty else {
            validationMessage = PMLocalized("Enter the IMAP host.")
            return
        }
        guard let port = Int(portText), port > 0 else {
            validationMessage = PMLocalized("Enter a valid IMAP port.")
            return
        }

        isSaving = true
        validationMessage = nil
        let resolvedDisplayName = cleanDisplayName.isEmpty ? provider.label : cleanDisplayName
        let snapshot = EmailAccountConnectionSnapshot(
            providerLabel: provider.label,
            displayName: resolvedDisplayName,
            emailAddress: cleanEmail,
            imapHost: cleanHost,
            imapPort: port,
            useTLS: useTLS,
            username: cleanUsername
        )

        Task {
            do {
                try await EmailAutoDiscoveryService.shared.validateConnection(
                    account: snapshot,
                    password: cleanPassword
                )

                let accountID = UUID()
                let key = EmailCredentialStore.makeKey(for: accountID)
                try EmailCredentialStore.savePassword(cleanPassword, key: key)
                let account = ConnectedEmailAccount(
                    id: accountID,
                    provider: provider,
                    displayName: resolvedDisplayName,
                    emailAddress: cleanEmail,
                    imapHost: cleanHost,
                    imapPort: port,
                    useTLS: useTLS,
                    username: cleanUsername,
                    passwordKeychainKey: key,
                    lastScanStatus: PMLocalized("Connection verified. Ready for automatic scan")
                )

                await MainActor.run {
                    modelContext.insert(account)
                    do {
                        try modelContext.save()
                        dismiss()
                    } catch {
                        validationMessage = error.localizedDescription
                        isSaving = false
                    }
                }
            } catch {
                await MainActor.run {
                    validationMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}
