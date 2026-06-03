//
//  EmailAutoDiscoveryService.swift
//  PayGuard
//
//  Connects to IMAP mailboxes and automatically searches recent emails for
//  subscription, receipt, renewal, and invoice signals.
//

import Foundation
import Network

enum EmailAutoDiscoveryError: LocalizedError {
    case missingPassword
    case connectionFailed
    case loginFailed(String)
    case commandFailed(String)
    case noMessagesFound

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            return "No saved password was found for this email account."
        case .connectionFailed:
            return "PayGuard could not connect to the email server."
        case .loginFailed(let message):
            let normalized = message.lowercased()
            if normalized.contains("authenticationfailed") || normalized.contains("invalid credentials") {
                return "Email login failed. For iCloud Mail, use your full Apple Account email address and an app-specific password from account.apple.com, not your normal Apple Account password."
            }
            return "Email login failed: \(message)"
        case .commandFailed(let message):
            return "Email scan failed: \(message)"
        case .noMessagesFound:
            return "No active subscription emails were found in the scanned mailboxes."
        }
    }
}

struct EmailScanConfiguration: Sendable {
    var maxMessagesToInspect: Int = 900
    var maxFindings: Int = 20
    var incrementalOverlapDays: Int = 2
    var previewFetchByteLimit: Int = 50_000
    var fullFetchByteLimit: Int = 180_000
    var strongServiceEarlyStopCount: Int = 5
}

struct EmailAccountConnectionSnapshot: Sendable {
    let id: UUID
    let providerLabel: String
    let displayName: String
    let emailAddress: String
    let imapHost: String
    let imapPort: Int
    let useTLS: Bool
    let username: String
    let passwordKeychainKey: String
    let selectedScanMailbox: String
    let lastScanAt: Date?

    init(
        id: UUID = UUID(),
        providerLabel: String,
        displayName: String,
        emailAddress: String,
        imapHost: String,
        imapPort: Int,
        useTLS: Bool,
        username: String,
        passwordKeychainKey: String = "",
        selectedScanMailbox: String = "INBOX",
        lastScanAt: Date? = nil
    ) {
        self.id = id
        self.providerLabel = providerLabel
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.useTLS = useTLS
        self.username = username
        self.passwordKeychainKey = passwordKeychainKey
        self.selectedScanMailbox = selectedScanMailbox
        self.lastScanAt = lastScanAt
    }

    init(account: ConnectedEmailAccount, lastScanAtOverride: Date? = nil) {
        self.id = account.id
        self.providerLabel = account.provider.label
        self.displayName = account.displayName
        self.emailAddress = account.emailAddress
        self.imapHost = account.imapHost
        self.imapPort = account.imapPort
        self.useTLS = account.useTLS
        self.username = account.username
        self.passwordKeychainKey = account.passwordKeychainKey
        self.selectedScanMailbox = account.selectedScanMailbox
        self.lastScanAt = lastScanAtOverride ?? account.lastScanAt
    }
}

final class EmailAutoDiscoveryService {
    static let shared = EmailAutoDiscoveryService()

    func validateConnection(
        account: EmailAccountConnectionSnapshot,
        password: String
    ) async throws {
        guard !password.isEmpty else { throw EmailAutoDiscoveryError.missingPassword }

        let client = IMAPClient(
            host: account.imapHost,
            port: account.imapPort,
            useTLS: account.useTLS
        )
        try await client.connect()
        defer { Task { try? await client.disconnect() } }

        _ = try await authenticate(client: client, account: account, password: password)

        let listResponse = try await client.listMailboxes()
        guard listResponse.isOK else {
            throw EmailAutoDiscoveryError.commandFailed(listResponse.raw)
        }

        let mailbox = parseMailboxNames(from: listResponse.raw).first(where: { $0.caseInsensitiveCompare("INBOX") == .orderedSame }) ?? "INBOX"
        let selectResponse = try await client.selectMailbox(mailbox)
        guard selectResponse.isOK else {
            throw EmailAutoDiscoveryError.commandFailed(selectResponse.raw)
        }
    }

    func availableMailboxes(
        account: EmailAccountConnectionSnapshot
    ) async throws -> [String] {
        let password = try EmailCredentialStore.password(for: account.passwordKeychainKey)
        guard !password.isEmpty else { throw EmailAutoDiscoveryError.missingPassword }

        let client = IMAPClient(
            host: account.imapHost,
            port: account.imapPort,
            useTLS: account.useTLS
        )
        try await client.connect()
        defer { Task { try? await client.disconnect() } }

        _ = try await authenticate(client: client, account: account, password: password)

        let response = try await client.listMailboxes()
        guard response.isOK else {
            throw EmailAutoDiscoveryError.commandFailed(response.raw)
        }

        let inboxFirst = parseMailboxNames(from: response.raw)
            .filter(shouldScanMailbox)
        var ordered: [String] = []
        var seen = Set<String>()
        for mailbox in inboxFirst {
            let key = mailbox.lowercased()
            guard seen.insert(key).inserted else { continue }
            if mailbox.caseInsensitiveCompare("INBOX") == .orderedSame {
                ordered.insert(mailbox, at: 0)
            } else {
                ordered.append(mailbox)
            }
        }

        return ordered.isEmpty ? ["INBOX"] : ordered
    }

    func scan(
        account: EmailAccountConnectionSnapshot,
        configuration: EmailScanConfiguration = EmailScanConfiguration(),
        onProgress: (@Sendable ([EmailScanFinding]) async -> Void)? = nil
    ) async throws -> [EmailScanFinding] {
        let password = try EmailCredentialStore.password(for: account.passwordKeychainKey)
        guard !password.isEmpty else { throw EmailAutoDiscoveryError.missingPassword }

        let client = IMAPClient(
            host: account.imapHost,
            port: account.imapPort,
            useTLS: account.useTLS
        )
        try await client.connect()
        defer { Task { try? await client.disconnect() } }

        _ = try await authenticate(client: client, account: account, password: password)

        let scanMailboxes = await resolvedScanMailboxes(
            using: client,
            preferredMailbox: account.selectedScanMailbox
        )
        let sinceDate = account.lastScanAt.flatMap {
            Calendar.current.date(byAdding: .day, value: -configuration.incrementalOverlapDays, to: $0)
        }
        let isIncrementalScan = sinceDate != nil
        var allEvents: [EmailScanEvent] = []
        var seenMessageKeys = Set<String>()
        var strongRecurringServiceKeys = Set<String>()
        var lastProgressSignature = ""

        for mailbox in scanMailboxes {
            let selectResponse = try await client.selectMailbox(mailbox)
            guard selectResponse.isOK else { continue }

            let uids = try await collectCandidateUIDs(
                client: client,
                since: sinceDate,
                configuration: configuration
            )

            for uid in uids {
                let previewResponse = try await client.uidFetchMessage(
                    uid: uid,
                    byteLimit: configuration.previewFetchByteLimit
                )
                guard previewResponse.isOK else { continue }

                let previewEvent = makeEvent(
                    from: previewResponse.raw,
                    account: account,
                    mailbox: mailbox
                )
                let event: EmailScanEvent?

                if let previewEvent {
                    if shouldUpgradeToFullFetch(for: previewEvent) {
                        let fullResponse = try await client.uidFetchMessage(
                            uid: uid,
                            byteLimit: configuration.fullFetchByteLimit
                        )
                        if fullResponse.isOK,
                           let fullEvent = makeEvent(
                            from: fullResponse.raw,
                            account: account,
                            mailbox: mailbox
                           ) {
                            event = fullEvent
                        } else {
                            event = previewEvent
                        }
                    } else {
                        event = previewEvent
                    }
                } else if shouldUpgradeToFullFetch(
                    previewRawMessage: previewResponse.raw,
                    account: account
                ) {
                    let fullResponse = try await client.uidFetchMessage(
                        uid: uid,
                        byteLimit: configuration.fullFetchByteLimit
                    )
                    if fullResponse.isOK {
                        event = makeEvent(
                            from: fullResponse.raw,
                            account: account,
                            mailbox: mailbox
                        )
                    } else {
                        event = nil
                    }
                } else {
                    event = nil
                }

                guard let event else { continue }
                guard seenMessageKeys.insert(event.messageKey).inserted else { continue }
                allEvents.append(event)

                if let onProgress {
                    let interimFindings = makeFindings(
                        from: allEvents,
                        account: account,
                        configuration: configuration
                    )
                    let signature = interimFindings
                        .map { $0.subject.normalizedLookupKey }
                        .joined(separator: "|")
                    if signature != lastProgressSignature {
                        lastProgressSignature = signature
                        await onProgress(interimFindings)
                    }
                }

                if isStrongRecurringCandidate(event) {
                    strongRecurringServiceKeys.insert(derivedServiceKey(for: event))
                }
                if !isIncrementalScan,
                   strongRecurringServiceKeys.count >= configuration.strongServiceEarlyStopCount {
                    break
                }
            }

            if !isIncrementalScan,
               strongRecurringServiceKeys.count >= configuration.strongServiceEarlyStopCount {
                break
            }
        }

        let findings = makeFindings(
            from: allEvents,
            account: account,
            configuration: configuration
        )
        if findings.isEmpty {
            throw EmailAutoDiscoveryError.noMessagesFound
        }
        return findings
    }

    private func collectCandidateUIDs(
        client: IMAPClient,
        since date: Date?,
        configuration: EmailScanConfiguration
    ) async throws -> [Int] {
        let baseCriterion = searchBaseCriterion(for: date)
        let isIncrementalScan = date != nil
        let priorityCriteria = [
            "\(baseCriterion) SUBJECT \"invoice\"",
            "\(baseCriterion) SUBJECT \"receipt\"",
            "\(baseCriterion) SUBJECT \"Rechnung\"",
            "\(baseCriterion) SUBJECT \"subscription\"",
            "\(baseCriterion) SUBJECT \"renewal\"",
            "\(baseCriterion) FROM \"Apple\"",
            "\(baseCriterion) FROM \"apple.com\"",
            "\(baseCriterion) FROM \"OpenAI\"",
            "\(baseCriterion) FROM \"ChatGPT\"",
            "\(baseCriterion) FROM \"Resume Genius\"",
            "\(baseCriterion) FROM \"resumegenius\"",
            "\(baseCriterion) FROM \"Resumaker\"",
            "\(baseCriterion) FROM \"resumaker\"",
            "\(baseCriterion) FROM \"Spotify\"",
            "\(baseCriterion) FROM \"Netflix\"",
            "\(baseCriterion) FROM \"Google\"",
            "\(baseCriterion) FROM \"Microsoft\"",
            "\(baseCriterion) FROM \"Adobe\""
        ]
        let secondaryCriteria = [
            "\(baseCriterion) SUBJECT \"cancel\"",
            "\(baseCriterion) SUBJECT \"billing\"",
            "\(baseCriterion) SUBJECT \"payment\"",
            "\(baseCriterion) SUBJECT \"trial\"",
            "\(baseCriterion) TEXT \"auto-renew\"",
            "\(baseCriterion) TEXT \"auto renew\"",
            "\(baseCriterion) TEXT \"renews on\"",
            "\(baseCriterion) TEXT \"next billing\"",
            "\(baseCriterion) TEXT \"next payment\"",
            "\(baseCriterion) TEXT \"billed every\"",
            "\(baseCriterion) TEXT \"recurring service\"",
            "\(baseCriterion) TEXT \"manage your subscription\"",
            "\(baseCriterion) TEXT \"trial remaining\"",
            "\(baseCriterion) TEXT \"subscription will continue\""
        ]
        let criteria: [String]

        if isIncrementalScan {
            criteria = priorityCriteria + secondaryCriteria + [baseCriterion]
        } else {
            // Full scans should favor the strongest billing candidates first.
            // That keeps Apple invoices/renewals and known providers ahead of
            // broader trial/marketing-adjacent subscription searches.
            criteria = priorityCriteria + secondaryCriteria
        }

        var ordered = [Int]()
        var seen = Set<Int>()
        var lastError: Error?
        let fullScanLimit = min(max(configuration.maxMessagesToInspect, 400), 700)
        let highPriorityCount = priorityCriteria.count
        let primaryPerCriterionLimit = isIncrementalScan ? configuration.maxMessagesToInspect : 70
        let secondaryPerCriterionLimit = isIncrementalScan ? configuration.maxMessagesToInspect : 35

        for (index, criterion) in criteria.enumerated() {
            do {
                let response = try await client.uidSearch(criteria: criterion)
                guard response.isOK else { continue }
                let matchedUIDs = parseUIDs(from: response.raw)
                let newestFirst = matchedUIDs.sorted(by: >)
                let perCriterionLimit = index < highPriorityCount ? primaryPerCriterionLimit : secondaryPerCriterionLimit
                let limitedUIDs = Array(newestFirst.prefix(perCriterionLimit))
                for uid in limitedUIDs where !seen.contains(uid) {
                    ordered.append(uid)
                    seen.insert(uid)
                }
                if !isIncrementalScan, ordered.count >= fullScanLimit {
                    break
                }
            } catch {
                lastError = error
            }
        }

        if ordered.isEmpty, let lastError {
            throw lastError
        }

        if isIncrementalScan {
            return Array(ordered.prefix(configuration.maxMessagesToInspect))
        }
        return Array(ordered.prefix(fullScanLimit))
    }

    private func shouldUpgradeToFullFetch(for event: EmailScanEvent) -> Bool {
        let serviceName = resolvedServiceName(for: event)
        let score = recurringEvidenceScore(for: event)

        if score <= 5 { return true }
        if event.explicitCycle == nil && event.nextBillingDate == nil { return true }
        if !isLikelyServiceNameLine(serviceName) { return true }
        if serviceName.normalizedLookupKey == event.subject.normalizedLookupKey,
           !event.hasRenewalCommitment,
           event.nextBillingDate == nil {
            return true
        }

        return false
    }

    private func shouldUpgradeToFullFetch(
        previewRawMessage rawMessage: String,
        account: EmailAccountConnectionSnapshot
    ) -> Bool {
        let extractedMessage = extractedIMAPMessageText(from: rawMessage)
        let (rawHeaderText, rawBodyText) = splitHeaderAndBody(from: extractedMessage)
        let readableBody = extractedReadableBody(fromHeaders: rawHeaderText, body: rawBodyText)
        let normalizedBody = normalizedMessageText(readableBody)
        let subject = decodeMIMEWords(headerValue("Subject", in: rawHeaderText) ?? "")
        let sender = decodeMIMEWords(headerValue("From", in: rawHeaderText) ?? account.emailAddress)
        let corpus = "\(subject)\n\(sender)\n\(normalizedBody)".lowercased()

        let strongHeaderSignals = [
            "invoice", "receipt", "rechnung", "subscription", "renewal", "billing",
            "payment", "trial", "apple", "app store", "openai", "chatgpt",
            "resume genius", "resumegenius", "spotify", "netflix", "google", "adobe"
        ]

        if strongHeaderSignals.contains(where: { corpus.contains($0) }) {
            return true
        }

        return likelyContainsMoneyOrRenewal(in: corpus)
    }

    private func isStrongRecurringCandidate(_ event: EmailScanEvent) -> Bool {
        guard !event.isCancellation else { return false }
        guard event.hasPaymentEvidence || event.hasRenewalCommitment else { return false }
        guard recurringEvidenceScore(for: event) >= 8 else { return false }
        return (event.explicitCycle?.isRecurring ?? false) ||
            event.nextBillingDate != nil ||
            containsRecurringLanguage(event.normalizedText)
    }

    private func authenticate(
        client: IMAPClient,
        account: EmailAccountConnectionSnapshot,
        password: String
    ) async throws -> String {
        var lastRawResponse: String?

        for username in loginCandidates(for: account) {
            let response = try await client.login(username: username, password: password)
            if response.isOK {
                return username
            }
            lastRawResponse = response.raw
        }

        throw EmailAutoDiscoveryError.loginFailed(lastRawResponse ?? "Authentication failed.")
    }

    private func loginCandidates(for account: EmailAccountConnectionSnapshot) -> [String] {
        var candidates: [String] = []

        let trimmedUsername = account.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = account.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedUsername.isEmpty {
            candidates.append(trimmedUsername)
        }

        if account.imapHost.caseInsensitiveCompare("imap.mail.me.com") == .orderedSame {
            if let localPart = trimmedEmail.split(separator: "@").first.map(String.init), !localPart.isEmpty {
                candidates.append(localPart)
            }
            if !trimmedEmail.isEmpty {
                candidates.append(trimmedEmail)
            }
        } else if !trimmedEmail.isEmpty {
            candidates.append(trimmedEmail)
        }

        var ordered: [String] = []
        var seen = Set<String>()
        for candidate in candidates {
            let key = candidate.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(candidate)
        }
        return ordered
    }

    private func searchBaseCriterion(for date: Date?) -> String {
        guard let date else { return "ALL" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MMM-yyyy"
        return "SINCE \(formatter.string(from: date))"
    }

    private func parseUIDs(from raw: String) -> [Int] {
        var ids = [Int]()
        let lines = raw.components(separatedBy: .newlines)
        guard let regex = try? NSRegularExpression(pattern: #"\b\d+\b"#) else { return [] }
        for line in lines where line.range(of: "SEARCH", options: .caseInsensitive) != nil {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            ids.append(contentsOf: matches.compactMap { Int(nsLine.substring(with: $0.range)) })
        }
        return ids.filter { $0 > 0 }
    }

    private func resolvedScanMailboxes(
        using client: IMAPClient,
        preferredMailbox: String
    ) async -> [String] {
        let trimmedPreferredMailbox = preferredMailbox.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreferredMailbox.isEmpty {
            return [trimmedPreferredMailbox]
        }

        guard let response = try? await client.listMailboxes(), response.isOK else {
            return ["INBOX"]
        }

        let parsed = parseMailboxNames(from: response.raw)
        if parsed.isEmpty {
            return ["INBOX"]
        }

        var ordered: [String] = []
        var seen = Set<String>()
        for mailbox in parsed where shouldScanMailbox(mailbox) {
            let key = mailbox.lowercased()
            guard seen.insert(key).inserted else { continue }
            if mailbox.caseInsensitiveCompare("INBOX") == .orderedSame {
                ordered.insert(mailbox, at: 0)
            } else {
                ordered.append(mailbox)
            }
        }

        return ordered.isEmpty ? ["INBOX"] : ordered
    }

    private func parseMailboxNames(from raw: String) -> [String] {
        raw
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard line.uppercased().contains(" LIST ") else { return nil }
                let lower = line.lowercased()
                guard !lower.contains("\\noselect") else { return nil }

                if let quotedRange = line.range(of: #""((?:[^"\\]|\\.)*)"\s*$"#, options: .regularExpression) {
                    let mailbox = String(line[quotedRange])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        .replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return mailbox.isEmpty ? nil : mailbox
                }

                let components = line.split(separator: " ")
                guard let last = components.last else { return nil }
                let mailbox = String(last).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return mailbox.isEmpty ? nil : mailbox
            }
    }

    private func shouldScanMailbox(_ mailbox: String) -> Bool {
        let lower = mailbox.lowercased()
        let blockedFragments = [
            "spam", "junk", "trash", "bin", "deleted", "draft", "sent", "outbox"
        ]
        return !blockedFragments.contains(where: { lower.contains($0) })
    }

    private func makeEvent(
        from rawMessage: String,
        account: EmailAccountConnectionSnapshot,
        mailbox: String
    ) -> EmailScanEvent? {
        let extractedMessage = extractedIMAPMessageText(from: rawMessage)
        let (rawHeaderText, rawBodyText) = splitHeaderAndBody(from: extractedMessage)
        let readableBody = extractedReadableBody(fromHeaders: rawHeaderText, body: rawBodyText)
        let preliminaryAppleDebugCandidate = shouldDebugAppleMessage(
            rawHeaders: rawHeaderText,
            rawBody: rawBodyText,
            normalizedBody: readableBody,
            subject: nil,
            sender: nil
        )
        let normalizedBody = normalizedMessageText(readableBody)
        guard !normalizedBody.isEmpty else {
            debugAppleMessage(
                isCandidate: preliminaryAppleDebugCandidate,
                decision: "drop",
                reason: "normalized body empty",
                mailbox: mailbox,
                subject: nil,
                sender: nil,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: nil
            )
            return nil
        }

        let subject = decodeMIMEWords(headerValue("Subject", in: rawHeaderText) ?? "Possible subscription email")
        let sender = decodeMIMEWords(headerValue("From", in: rawHeaderText) ?? account.emailAddress)
        let dateText = headerValue("Date", in: rawHeaderText) ?? ""
        let appleDebugCandidate = shouldDebugAppleMessage(
            rawHeaders: rawHeaderText,
            rawBody: rawBodyText,
            normalizedBody: normalizedBody,
            subject: subject,
            sender: sender
        )

        let lowercased = normalizedBody.lowercased()
        let subjectLower = subject.lowercased()
        let senderLower = sender.lowercased()
        let headerSignals = "\(subject) \(sender) \(account.providerLabel)".lowercased()
        let appleInvoiceDetails = extractAppleRecurringInvoiceDetails(
            from: normalizedBody,
            subject: subject,
            sender: sender
        )
        let recurringSignals = appleInvoiceDetails != nil || containsRecurringLanguage(normalizedBody) || containsRecurringLanguage(subject)
        let subscriptionSignals = [
            "subscription", "renewal", "renew", "auto-renew", "auto renew", "recurring",
            "monthly", "yearly", "weekly", "annual", "billed every", "next billing",
            "next payment", "membership", "mitgliedschaft", "abonnement", "abo",
            "apple.com/bill", "google play", "netflix", "spotify", "icloud+", "google one",
            "microsoft 365", "adobe", "canva", "chatgpt"
        ]
        let transactionalSignals = [
            "receipt", "invoice", "payment", "charged", "billing", "rechnung", "zahlung"
        ]
        let signalCorpus = lowercased + "\n" + headerSignals
        let signalScore = subscriptionSignals.reduce(0) { partial, signal in
            partial + (signalCorpus.contains(signal) ? 1 : 0)
        }
        let transactionalScore = transactionalSignals.reduce(0) { partial, signal in
            partial + (signalCorpus.contains(signal) ? 1 : 0)
        }
        let knownProviderSignals = [
            "apple", "itunes", "app store", "spotify", "netflix", "google", "youtube",
            "microsoft", "adobe", "canva", "dropbox", "notion", "openai", "chatgpt"
        ]
        let cancellationKeywords = [
            "cancelled", "canceled", "subscription cancelled", "subscription canceled",
            "will not renew", "won't renew", "ended", "has ended", "expires on",
            "cancel your subscription", "cancelation confirmed", "cancellation confirmed",
            "gekündigt", "gekundigt", "wird nicht verlängert", "nicht erneuert"
        ]
        let hasCancellationSignal = cancellationKeywords.contains { lowercased.contains($0) }

        let knownProviderSender = knownProviderSignals.contains { headerSignals.contains($0) }
        let invoiceSubject = ["invoice", "receipt", "rechnung", "beleg", "quittung", "purchase", "rechnung von"].contains { headerSignals.contains($0) }
        let trustedHeaderMatch = knownProviderSender && invoiceSubject
        let explicitNextBillingDate = appleInvoiceDetails?.nextBillingDate ?? detectedDate(
            in: normalizedBody,
            matchingAnyOf: [
                "next billing", "next payment", "next charge", "renews on",
                "renewal date", "billing date", "renews", "valid until"
            ],
            preferFuture: true
        )
        let explicitCycle = appleInvoiceDetails?.cycle ?? detectedRecurringCycle(in: normalizedBody + "\n" + subject)
        let hasSubscriptionContext = appleInvoiceDetails != nil || containsSubscriptionContext(in: normalizedBody, subject: subject, sender: sender)
        let amountText = appleInvoiceDetails?.amountText ?? detectedSubscriptionAmount(in: normalizedBody)
        let serviceName = appleInvoiceDetails?.serviceName ?? inferredServiceName(subject: subject, sender: sender, text: normalizedBody)
        let hasPaymentEvidence = amountText != nil || containsCompletedPaymentLanguage(in: normalizedBody) || trustedHeaderMatch
        let hasRenewalCommitment = containsRenewalCommitmentLanguage(in: normalizedBody)
        let isAppleMail = isAppleMessage(subject: subject, sender: sender, text: normalizedBody)
        let hasStrongAppleSubscriptionSignals = containsStrongAppleSubscriptionSignals(
            subject: subject,
            sender: sender,
            text: normalizedBody
        )

        let signalSummary = """
        signalScore=\(signalScore) transactionalScore=\(transactionalScore) recurringSignals=\(recurringSignals) trustedHeaderMatch=\(trustedHeaderMatch) explicitCycle=\(explicitCycle?.rawValue ?? "nil") explicitNextBillingDate=\(explicitNextBillingDate?.description ?? "nil") amountText=\(amountText ?? "nil") serviceName=\(serviceName) hasPaymentEvidence=\(hasPaymentEvidence) hasRenewalCommitment=\(hasRenewalCommitment) hasSubscriptionContext=\(hasSubscriptionContext) appleInvoiceDetails=\(appleInvoiceDetails != nil)
        """

        guard signalScore > 0 || trustedHeaderMatch || hasCancellationSignal else {
            debugAppleMessage(
                isCandidate: appleDebugCandidate,
                decision: "drop",
                reason: "failed signalScore/trusted header gate",
                mailbox: mailbox,
                subject: subject,
                sender: sender,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: signalSummary
            )
            return nil
        }
        guard !isAppleMail || hasCancellationSignal || appleInvoiceDetails != nil || hasStrongAppleSubscriptionSignals else {
            debugAppleMessage(
                isCandidate: appleDebugCandidate,
                decision: "drop",
                reason: "failed apple-specific billing gate",
                mailbox: mailbox,
                subject: subject,
                sender: sender,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: signalSummary
            )
            return nil
        }
        guard recurringSignals || explicitCycle?.isRecurring == true || explicitNextBillingDate != nil || trustedHeaderMatch || hasCancellationSignal else {
            debugAppleMessage(
                isCandidate: appleDebugCandidate,
                decision: "drop",
                reason: "failed recurring evidence gate",
                mailbox: mailbox,
                subject: subject,
                sender: sender,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: signalSummary
            )
            return nil
        }
        guard likelyContainsMoneyOrRenewal(in: lowercased) || trustedHeaderMatch || hasCancellationSignal else {
            debugAppleMessage(
                isCandidate: appleDebugCandidate,
                decision: "drop",
                reason: "failed money/renewal gate",
                mailbox: mailbox,
                subject: subject,
                sender: sender,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: signalSummary
            )
            return nil
        }
        guard transactionalScore > 0 || recurringSignals || explicitNextBillingDate != nil || hasCancellationSignal else {
            debugAppleMessage(
                isCandidate: appleDebugCandidate,
                decision: "drop",
                reason: "failed transactional/recurring gate",
                mailbox: mailbox,
                subject: subject,
                sender: sender,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: signalSummary
            )
            return nil
        }

        let preview = normalizedBody
            .components(separatedBy: .newlines)
            .filter { !isNoisePreviewLine($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(12)
            .joined(separator: "\n")

        let confidence = min(0.98, 0.50 + (Double(signalScore) * 0.08) + (trustedHeaderMatch ? 0.24 : 0.0))
        let receivedAt = parsedHeaderDate(from: dateText)
        let explicitChargeDate = detectedDate(
            in: normalizedBody,
            matchingAnyOf: [
                "invoice date", "purchase date", "charged on", "payment date",
                "order date", "billed on", "invoice", "receipt date"
            ],
            preferFuture: false
        ) ?? receivedAt ?? detectedRelevantDate(in: normalizedBody, preferFuture: false)
        let senderLooksTransactional = senderLower.contains("no-reply") || senderLower.contains("receipt") || senderLower.contains("billing")

        let hasExplicitRecurringPlan = explicitCycle?.isRecurring == true
        let hasRecurringEvidence = hasExplicitRecurringPlan || explicitNextBillingDate != nil || recurringSignals
        let hasActionableSubscriptionEvidence = hasPaymentEvidence || hasRenewalCommitment
        let shouldKeep = hasCancellationSignal ||
            (hasRecurringEvidence && hasActionableSubscriptionEvidence && hasSubscriptionContext) ||
            (appleInvoiceDetails != nil && hasRecurringEvidence) ||
            (trustedHeaderMatch && hasActionableSubscriptionEvidence) ||
            (senderLooksTransactional && hasRecurringEvidence && hasActionableSubscriptionEvidence && hasSubscriptionContext)
        guard shouldKeep else {
            debugAppleMessage(
                isCandidate: appleDebugCandidate,
                decision: "drop",
                reason: "failed shouldKeep gate",
                mailbox: mailbox,
                subject: subject,
                sender: sender,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: signalSummary
            )
            return nil
        }
        guard !serviceName.hasPrefix("* ") else {
            debugAppleMessage(
                isCandidate: appleDebugCandidate,
                decision: "drop",
                reason: "service name parsed as IMAP noise",
                mailbox: mailbox,
                subject: subject,
                sender: sender,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: signalSummary
            )
            return nil
        }
        guard !subjectLower.hasPrefix("re:") || hasSubscriptionContext else {
            debugAppleMessage(
                isCandidate: appleDebugCandidate,
                decision: "drop",
                reason: "reply subject without subscription context",
                mailbox: mailbox,
                subject: subject,
                sender: sender,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: signalSummary
            )
            return nil
        }
        guard hasActionableSubscriptionEvidence || hasCancellationSignal else {
            debugAppleMessage(
                isCandidate: appleDebugCandidate,
                decision: "drop",
                reason: "no actionable subscription evidence",
                mailbox: mailbox,
                subject: subject,
                sender: sender,
                rawHeaders: rawHeaderText,
                readableBody: readableBody,
                normalizedBody: normalizedBody,
                signalSummary: signalSummary
            )
            return nil
        }

        let event = EmailScanEvent(
            serviceName: serviceName,
            mailbox: mailbox,
            subject: subject,
            sender: sender,
            dateText: dateText,
            preview: preview,
            normalizedText: normalizedBody,
            receivedAt: receivedAt,
            eventDate: explicitChargeDate ?? .now,
            nextBillingDate: explicitNextBillingDate,
            amountText: amountText,
            currencyCode: detectedCurrency(in: normalizedBody),
            explicitCycle: explicitCycle,
            isCancellation: hasCancellationSignal,
            hasPaymentEvidence: hasPaymentEvidence,
            hasRenewalCommitment: hasRenewalCommitment,
            confidence: confidence
        )
        debugAppleMessage(
            isCandidate: appleDebugCandidate,
            decision: "keep",
            reason: "event accepted",
            mailbox: mailbox,
            subject: subject,
            sender: sender,
            rawHeaders: rawHeaderText,
            readableBody: readableBody,
            normalizedBody: normalizedBody,
            signalSummary: signalSummary
        )
        return event
    }

    private func likelyContainsMoneyOrRenewal(in text: String) -> Bool {
        let moneyPattern = #"(€|eur|usd|\$|gbp|£|try|tl)\s?\d|\d+[\.,]\d{2}\s?(€|eur|usd|\$|gbp|£|try|tl)"#
        if text.range(of: moneyPattern, options: .regularExpression) != nil { return true }
        return [
            "monthly", "yearly", "annual", "next billing", "renews", "renewal", "monatlich",
            "jährlich", "abo", "abonnement", "cancelled", "canceled", "expires on", "subscription"
        ].contains { text.contains($0) }
    }

    private func headerValue(_ name: String, in message: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?im)^\(escaped):\\s*(.+(?:\\n[ \\t].+)*)"
        guard let range = message.range(of: pattern, options: .regularExpression) else { return nil }
        let line = String(message[range])
        return line
            .replacingOccurrences(of: "(?im)^\(escaped):\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n\t", with: " ")
            .replacingOccurrences(of: "\n ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedMessageText(_ raw: String) -> String {
        let lineNormalized = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "=\n", with: "")

        let quotedPrintableDecoded = decodeQuotedPrintable(lineNormalized)
        let markupCleaned = quotedPrintableDecoded
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<!--.*?-->"#, with: " ", options: .regularExpression)
        let htmlCleaned = markupCleaned
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&euro;", with: "€")

        return htmlCleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isNoisePreviewLine($0) }
            .joined(separator: "\n")
    }

    private func extractedReadableBody(fromHeaders headers: String, body: String) -> String {
        let normalizedHeaders = headers.replacingOccurrences(of: "\r\n", with: "\n")
        let normalizedBody = body.replacingOccurrences(of: "\r\n", with: "\n")
        let extractedParts = extractRenderableBodies(fromHeaders: normalizedHeaders, body: normalizedBody, depth: 0)

        let candidates = (extractedParts.plain + extractedParts.html)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { bodyScore($0) > bodyScore($1) }
        if !candidates.isEmpty {
            return candidates.joined(separator: "\n")
        }

        let topLevelEncoding = headerValue("Content-Transfer-Encoding", in: normalizedHeaders)?.lowercased() ?? ""
        return decodedBody(normalizedBody, transferEncoding: topLevelEncoding)
    }

    private func extractRenderableBodies(
        fromHeaders headers: String,
        body: String,
        depth: Int
    ) -> (plain: [String], html: [String]) {
        guard depth < 6 else { return ([], []) }

        let contentType = headerValue("Content-Type", in: headers)?.lowercased() ?? ""
        let transferEncoding = headerValue("Content-Transfer-Encoding", in: headers)?.lowercased() ?? ""

        if contentType.contains("multipart/"), let boundary = mimeBoundary(in: headers) {
            let delimiter = "--\(boundary)"
            let endDelimiter = "--\(boundary)--"
            let parts = body
                .components(separatedBy: delimiter)
                .map { $0.replacingOccurrences(of: endDelimiter, with: "") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var plainParts: [String] = []
            var htmlParts: [String] = []

            for part in parts {
                let (partHeaders, partBody) = splitHeaderAndBody(from: part)
                let nested = extractRenderableBodies(
                    fromHeaders: partHeaders,
                    body: partBody,
                    depth: depth + 1
                )
                plainParts.append(contentsOf: nested.plain)
                htmlParts.append(contentsOf: nested.html)
            }

            return (plainParts, htmlParts)
        }

        let decoded = decodedBody(body, transferEncoding: transferEncoding)
        guard !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ([], []) }

        if contentType.contains("text/plain") {
            return ([decoded], [])
        }
        if contentType.contains("text/html") {
            return ([], [decoded])
        }

        if contentType.isEmpty {
            return ([decoded], [])
        }

        return ([], [])
    }

    private func mimeBoundary(in headers: String) -> String? {
        if let quoted = firstMatch(
            pattern: #"(?im)boundary="([^"\n]+)""#,
            in: headers
        ) {
            return quoted
        }

        return firstMatch(
            pattern: #"(?im)boundary=([^\s;]+)"#,
            in: headers
        )
    }

    private func decodedBody(_ body: String, transferEncoding: String) -> String {
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")

        if transferEncoding.contains("base64") {
            let compact = normalized
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined()
            if let data = Data(base64Encoded: compact, options: [.ignoreUnknownCharacters]) {
                if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
                    return utf8
                }
                if let latin1 = String(data: data, encoding: .isoLatin1), !latin1.isEmpty {
                    return latin1
                }
            }
        }

        if transferEncoding.contains("quoted-printable") {
            return decodeQuotedPrintable(normalized)
        }

        return normalized
    }

    private func bodyScore(_ text: String) -> Int {
        let lower = text.lowercased()
        var score = min(text.count / 80, 40)

        let strongSignals = [
            "app store",
            "your invoice from apple",
            "(monthly)",
            "(yearly)",
            "(weekly)",
            "renews",
            "subscription",
            "invoice",
            "receipt",
            "inclusive of vat"
        ]

        for signal in strongSignals where lower.contains(signal) {
            score += 25
        }

        if lower.contains("devicename") || lower.contains("purchasedatetime") {
            score += 8
        }

        if lower.contains("<html") || lower.contains("</table>") {
            score += 6
        }

        return score
    }

    private func shouldDebugAppleMessage(
        rawHeaders: String,
        rawBody: String,
        normalizedBody: String,
        subject: String?,
        sender: String?
    ) -> Bool {
        let corpus = [
            rawHeaders,
            normalizedBody,
            subject ?? "",
            sender ?? ""
        ]
        .joined(separator: "\n")
        .lowercased()

        let appleSignals = [
            "no reply@email.apple.com",
            "no_reply@email.apple.com",
            "noreply@email.apple.com",
            "email.apple.com",
            "insideapple.apple.com",
            "itunes",
            "app store",
            "apple account"
        ]
        let billingSignals = [
            "your invoice from apple",
            "your subscription renewal",
            "subscription renewal",
            "manage your subscription",
            "report a problem",
            "apple.com/bill",
            "(monthly)",
            "(yearly)",
            "(weekly)",
            "renews "
        ]
        return appleSignals.contains(where: { corpus.contains($0) }) &&
            billingSignals.contains(where: { corpus.contains($0) })
    }

    private func debugAppleMessage(
        isCandidate: Bool,
        decision: String,
        reason: String,
        mailbox: String,
        subject: String?,
        sender: String?,
        rawHeaders: String,
        readableBody: String,
        normalizedBody: String,
        signalSummary: String?
    ) {
#if DEBUG
        guard isCandidate else { return }
        let headerPreview = String(rawHeaders.prefix(1000))
        let readablePreview = String(readableBody.prefix(2500))
        let normalizedPreview = String(normalizedBody.prefix(2500))
        print("""
        [PayGuard][EmailDebug][Apple][\(decision.uppercased())]
        reason: \(reason)
        mailbox: \(mailbox)
        subject: \(subject ?? "nil")
        sender: \(sender ?? "nil")
        \(signalSummary ?? "")
        ---- HEADERS ----
        \(headerPreview)
        ---- READABLE BODY ----
        \(readablePreview)
        ---- NORMALIZED BODY ----
        \(normalizedPreview)
        [PayGuard][EmailDebug][Apple][END]
        """)
#endif
    }

    private func splitHeaderAndBody(from raw: String) -> (header: String, body: String) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if let range = normalized.range(of: "\n\n") {
            let header = String(normalized[..<range.lowerBound])
            let body = String(normalized[range.upperBound...])
            return (header, body)
        }
        return (normalized, normalized)
    }

    private func extractedIMAPMessageText(from raw: String) -> String {
        var normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        normalized = normalized.replacingOccurrences(
            of: #"(?m)^\* \d+ FETCH \(UID \d+ BODY\[\](?:<\d+\.\d+>)? \{\d+\}\s*$"#,
            with: "",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(
            of: #"(?m)^A\d+\s+OK UID FETCH completed\s*$"#,
            with: "",
            options: .regularExpression
        )
        let lines = normalized.components(separatedBy: .newlines)
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if let firstHeaderIndex = trimmed.firstIndex(where: { line in
            line.lowercased().hasPrefix("return-path:") ||
            line.lowercased().hasPrefix("from:") ||
            line.lowercased().hasPrefix("subject:") ||
            line.lowercased().hasPrefix("date:")
        }) {
            var contentLines = Array(lines[firstHeaderIndex...])
            while let line = contentLines.last {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.hasPrefix("A") || trimmedLine == ")" || trimmedLine.hasSuffix(" OK UID FETCH completed") {
                    contentLines.removeLast()
                } else {
                    break
                }
            }
            return contentLines.joined(separator: "\n")
        }

        return normalized
    }

    private func decodeMIMEWords(_ value: String) -> String {
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length)).reversed()
        var result = value

        for match in matches {
            guard match.numberOfRanges == 4 else { continue }
            let encoding = nsValue.substring(with: match.range(at: 2)).uppercased()
            let encoded = nsValue.substring(with: match.range(at: 3))
            let decoded: String?
            if encoding == "B" {
                decoded = Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) }
            } else {
                decoded = decodeQuotedPrintable(encoded.replacingOccurrences(of: "_", with: " "))
            }
            if let decoded {
                let range = Range(match.range, in: result)!
                result.replaceSubrange(range, with: decoded)
            }
        }

        return decodeQuotedPrintable(result.replacingOccurrences(of: "_", with: " "))
    }

    private func decodeQuotedPrintable(_ value: String) -> String {
        var bytes = [UInt8]()
        let scalars = Array(value.unicodeScalars)
        var index = 0

        while index < scalars.count {
            if scalars[index] == "=", index + 2 < scalars.count {
                let hex = String(String.UnicodeScalarView([scalars[index + 1], scalars[index + 2]]))
                if let byte = UInt8(hex, radix: 16) {
                    bytes.append(byte)
                    index += 3
                    continue
                }
            }

            let string = String(scalars[index])
            bytes.append(contentsOf: string.utf8)
            index += 1
        }

        return String(data: Data(bytes), encoding: .utf8) ?? value
    }

    private func makeFindings(
        from events: [EmailScanEvent],
        account: EmailAccountConnectionSnapshot,
        configuration: EmailScanConfiguration
    ) -> [EmailScanFinding] {
        let grouped = Dictionary(grouping: events, by: derivedServiceKey(for:))
        var findingsByKey: [String: EmailScanFinding] = [:]

        for (serviceKey, group) in grouped {
            guard let finding = finding(for: group, account: account) else { continue }
            findingsByKey[serviceKey] = finding
        }

        let fallbackEvents = events
            .sorted {
                let lhsScore = recurringEvidenceScore(for: $0)
                let rhsScore = recurringEvidenceScore(for: $1)
                if lhsScore == rhsScore {
                    return $0.eventDate > $1.eventDate
                }
                return lhsScore > rhsScore
            }

        for event in fallbackEvents {
            let serviceKey = derivedServiceKey(for: event)
            guard findingsByKey[serviceKey] == nil else { continue }
            guard let finding = fallbackFinding(for: event, account: account) else { continue }
            findingsByKey[serviceKey] = finding
        }

        return findingsByKey.values
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.subject.localizedCaseInsensitiveCompare(rhs.subject) == .orderedAscending
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(configuration.maxFindings)
            .map { $0 }
    }

    private func finding(
        for group: [EmailScanEvent],
        account: EmailAccountConnectionSnapshot
    ) -> EmailScanFinding? {
        let paidEvents = group.filter { !$0.isCancellation && $0.hasPaymentEvidence }
        let actionableEvents = group.filter { !$0.isCancellation && ($0.hasPaymentEvidence || $0.hasRenewalCommitment) }
        let referenceEvents = paidEvents.isEmpty ? actionableEvents : paidEvents
        guard !referenceEvents.isEmpty else { return nil }

        let representative = referenceEvents.max { lhs, rhs in
            let lhsScore = recurringEvidenceScore(for: lhs)
            let rhsScore = recurringEvidenceScore(for: rhs)
            if lhsScore == rhsScore {
                return lhs.eventDate < rhs.eventDate
            }
            return lhsScore < rhsScore
        }
        guard let latestPositive = representative else { return nil }

        if let latestCancellation = group
            .filter(\.isCancellation)
            .max(by: { $0.eventDate < $1.eventDate }),
           latestCancellation.eventDate >= latestPositive.eventDate {
            return nil
        }

        let cycle = inferredRecurringCycle(from: group)
        guard let cycle, cycle.isRecurring else { return nil }
        let nextPaymentDate = resolvedNextPaymentDate(from: latestPositive, cycle: cycle)
        let recurringSignals = group.filter {
            ($0.explicitCycle?.isRecurring ?? false) ||
            $0.nextBillingDate != nil ||
            $0.hasRenewalCommitment ||
            containsRecurringLanguage($0.normalizedText)
        }.count

        guard nextPaymentDate != nil || paidEvents.count > 1 || recurringSignals > 0 else {
            return nil
        }

        let serviceName = resolvedServiceName(for: latestPositive)
        let synthesizedText = synthesizedPayloadText(
            for: latestPositive,
            cycle: cycle,
            nextPaymentDate: nextPaymentDate,
            account: account,
            relatedEvents: actionableEvents.count
        )
        let summaryDate = nextPaymentDate ?? latestPositive.eventDate
        let confidence = min(0.99, latestPositive.confidence + (Double(min(actionableEvents.count, 3)) * 0.04))

        return EmailScanFinding(
            accountID: account.id,
            accountLabel: account.displayName,
            subject: serviceName,
            sender: latestPositive.sender,
            dateText: PayGuardFormatters.mediumDate.string(from: summaryDate),
            confidence: confidence,
            preview: latestPositive.preview,
            detectedServiceName: serviceName,
            detectedCategory: inferredSubscriptionCategory(from: latestPositive),
            detectedAmountText: latestPositive.amountText,
            detectedCurrencyCode: latestPositive.currencyCode,
            detectedBillingCycle: cycle,
            detectedNextPaymentDate: nextPaymentDate,
            detectedEventDate: latestPositive.eventDate,
            payload: SmartImportPayload(
                text: synthesizedText,
                sourceName: "\(account.providerLabel) • \(serviceName)"
            )
        )
    }

    private func fallbackFinding(
        for event: EmailScanEvent,
        account: EmailAccountConnectionSnapshot
    ) -> EmailScanFinding? {
        guard !event.isCancellation else { return nil }
        let cycle = event.explicitCycle ?? detectedRecurringCycle(in: event.normalizedText)
        guard let cycle, cycle.isRecurring else { return nil }
        guard event.hasPaymentEvidence || event.hasRenewalCommitment || event.nextBillingDate != nil else { return nil }

        let serviceName = resolvedServiceName(for: event)
        let nextPaymentDate = resolvedNextPaymentDate(from: event, cycle: cycle)
        let synthesizedText = synthesizedPayloadText(
            for: event,
            cycle: cycle,
            nextPaymentDate: nextPaymentDate,
            account: account,
            relatedEvents: 1
        )
        let summaryDate = nextPaymentDate ?? event.eventDate

        return EmailScanFinding(
            accountID: account.id,
            accountLabel: account.displayName,
            subject: serviceName,
            sender: event.sender,
            dateText: PayGuardFormatters.mediumDate.string(from: summaryDate),
            confidence: min(0.99, event.confidence + 0.02),
            preview: event.preview,
            detectedServiceName: serviceName,
            detectedCategory: inferredSubscriptionCategory(from: event),
            detectedAmountText: event.amountText,
            detectedCurrencyCode: event.currencyCode,
            detectedBillingCycle: cycle,
            detectedNextPaymentDate: nextPaymentDate,
            detectedEventDate: event.eventDate,
            payload: SmartImportPayload(
                text: synthesizedText,
                sourceName: "\(account.providerLabel) • \(serviceName)"
            )
        )
    }

    private func recurringEvidenceScore(for event: EmailScanEvent) -> Int {
        var score = 0
        if event.hasPaymentEvidence { score += 3 }
        if event.hasRenewalCommitment { score += 3 }
        if event.nextBillingDate != nil { score += 4 }
        if event.explicitCycle?.isRecurring == true { score += 4 }
        if containsRecurringLanguage(event.normalizedText) { score += 2 }
        if isAppleMessage(subject: event.subject, sender: event.sender, text: event.normalizedText) { score += 1 }
        return score
    }

    private func derivedServiceKey(for event: EmailScanEvent) -> String {
        resolvedServiceName(for: event).normalizedLookupKey
    }

    private func resolvedServiceName(for event: EmailScanEvent) -> String {
        let current = canonicalServiceName(from: event.serviceName)
        let currentLower = current.lowercased()
        if isLikelyServiceNameLine(current),
           !isGenericAppleInstructionLine(currentLower) {
            return current
        }

        if isAppleMessage(subject: event.subject, sender: event.sender, text: event.normalizedText) {
            let lines = event.normalizedText
                .components(separatedBy: .newlines)
                .map(cleanedServiceLine)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if let appleServiceName = appleSubscriptionServiceName(from: lines) {
                return appleServiceName
            }
        }

        return current
    }

    private func inferredRecurringCycle(from events: [EmailScanEvent]) -> BillingCycle? {
        let directCycle = events
            .sorted { $0.eventDate > $1.eventDate }
            .compactMap(\.explicitCycle)
            .first(where: \.isRecurring)
        if let directCycle {
            return directCycle
        }

        let positiveEvents = events
            .filter { !$0.isCancellation && $0.hasPaymentEvidence }
            .sorted { $0.eventDate > $1.eventDate }

        if let latest = positiveEvents.first,
           let nextBillingDate = latest.nextBillingDate {
            let dayDelta = abs(Calendar.current.dateComponents([.day], from: latest.eventDate.startOfDay, to: nextBillingDate.startOfDay).day ?? 0)
            if (6...8).contains(dayDelta) { return .weekly }
            if (27...35).contains(dayDelta) { return .monthly }
            if (80...100).contains(dayDelta) { return .quarterly }
            if (350...380).contains(dayDelta) { return .yearly }
        }

        if positiveEvents.count >= 2 {
            let newest = positiveEvents[0].eventDate.startOfDay
            let previous = positiveEvents[1].eventDate.startOfDay
            let dayDelta = abs(Calendar.current.dateComponents([.day], from: previous, to: newest).day ?? 0)
            if (6...8).contains(dayDelta) { return .weekly }
            if (27...35).contains(dayDelta) { return .monthly }
            if (80...100).contains(dayDelta) { return .quarterly }
            if (350...380).contains(dayDelta) { return .yearly }
        }

        return nil
    }

    private func containsCompletedPaymentLanguage(in text: String) -> Bool {
        let lower = text.lowercased()
        let positiveSignals = [
            "invoice", "receipt", "charged", "billed", "payment received",
            "payment successful", "purchase date", "order id", "document no",
            "inclusive of vat", "total", "subtotal", "renews", "renews on"
        ]
        let blockedSignals = [
            "payment failed", "payment due", "complete your purchase", "trial",
            "start your free", "verify your payment", "quote", "estimate", "reminder"
        ]
        guard !blockedSignals.contains(where: { lower.contains($0) }) else { return false }
        return positiveSignals.contains(where: { lower.contains($0) })
    }

    private func containsRenewalCommitmentLanguage(in text: String) -> Bool {
        let lower = text.lowercased()
        let strongSignals = [
            "auto-renews on",
            "subscription auto-renews",
            "will auto-renew on",
            "will renew on",
            "renews on",
            "billed every",
            "recurring service",
            "days remaining on your trial",
            "remaining on your trial",
            "before your subscription auto-renews",
            "trial before your subscription auto-renews",
            "trial ends on"
        ]
        let blockedSignals = [
            "trial has ended",
            "free trial available",
            "start your free trial",
            "payment failed",
            "renewal failed"
        ]
        guard !blockedSignals.contains(where: { lower.contains($0) }) else { return false }
        return strongSignals.contains(where: { lower.contains($0) })
    }

    private func containsSubscriptionContext(in text: String, subject: String, sender: String) -> Bool {
        let corpus = "\(text)\n\(subject)\n\(sender)".lowercased()
        let strongSignals = [
            "subscription", "renews", "renewal", "auto-renews", "auto renews", "app store", "itunes", "google play",
            "membership", "abonnement", "abo", "(monthly)", "(yearly)", "(weekly)",
            "(3 months)", "quarterly", "/3 months", "monthly plan", "annual plan", "yearly plan", "weekly plan",
            "quarterly plan", "plan:", "billed every",
            "recurring service", "trial remaining", "manage your subscription", "report a problem"
        ]
        let blockedSignals = [
            "smtp id", "media markt", "nur bis", "newsletter", "promotion", "discount",
            "sale", "angebot", "coupon", "ticket", "tuition", "support team", "livekit team",
            "creator studio", "review of your", "submission is complete", "apple developer",
            "insideapple.apple.com", "find my"
        ]
        guard !blockedSignals.contains(where: { corpus.contains($0) }) else { return false }
        return strongSignals.contains(where: { corpus.contains($0) })
    }

    private func isAppleMessage(subject: String, sender: String, text: String) -> Bool {
        let corpus = "\(subject)\n\(sender)\n\(text)".lowercased()
        return [
            "email.apple.com",
            "insideapple.apple.com",
            "itunes",
            "app store",
            "apple account",
            "apple creator studio"
        ].contains(where: { corpus.contains($0) }) || sender.lowercased().contains("apple")
    }

    private func containsStrongAppleSubscriptionSignals(subject: String, sender: String, text: String) -> Bool {
        let corpus = "\(subject)\n\(sender)\n\(text)".lowercased()
        let strongSignals = [
            "your invoice from apple",
            "your subscription renewal",
            "subscription renewal",
            "manage your subscription",
            "report a problem",
            "apple.com/bill",
            "document no",
            "purchase date",
            "invoice date",
            "inclusive of vat",
            "subscription auto-renews",
            "will auto-renew on",
            "will renew on",
            "renews on",
            "(monthly)",
            "(yearly)",
            "(weekly)",
            "(3 months)",
            "/3 months",
            "quarterly",
            "billed every 4 weeks"
        ]
        return strongSignals.contains(where: { corpus.contains($0) })
    }

    private func resolvedNextPaymentDate(from event: EmailScanEvent, cycle: BillingCycle?) -> Date? {
        if let nextBillingDate = event.nextBillingDate {
            guard let cycle, cycle.isRecurring else { return nextBillingDate }
            var rollingDate = nextBillingDate
            while rollingDate < .now.startOfDay {
                guard let advanced = advanced(date: rollingDate, by: cycle) else { break }
                rollingDate = advanced
            }
            return rollingDate
        }

        guard let cycle, cycle.isRecurring,
              var rollingDate = advanced(date: event.eventDate, by: cycle) else {
            return nil
        }

        while rollingDate < .now.startOfDay {
            guard let advanced = advanced(date: rollingDate, by: cycle) else { break }
            rollingDate = advanced
        }
        return rollingDate
    }

    private func advanced(date: Date, by cycle: BillingCycle) -> Date? {
        switch cycle {
        case .weekly:
            return Calendar.current.date(byAdding: .day, value: 7, to: date)
        case .monthly:
            return Calendar.current.date(byAdding: .month, value: 1, to: date)
        case .quarterly:
            return Calendar.current.date(byAdding: .month, value: 3, to: date)
        case .yearly:
            return Calendar.current.date(byAdding: .year, value: 1, to: date)
        default:
            return nil
        }
    }

    private func containsRecurringLanguage(_ text: String) -> Bool {
        let lower = text.lowercased()
        return [
            "subscription", "monthly", "yearly", "annual", "renews", "renewal",
            "auto-renew", "auto renew", "recurring", "every month", "every year",
            "quarterly", "every 3 months", "/3 months",
            "monatlich", "jährlich", "abonnement", "abo", "renews on", "next billing",
            "next payment", "billed every", "(monthly)", "(yearly)", "(weekly)",
            "every 4 weeks"
        ].contains { lower.contains($0) }
    }

    private func detectedSubscriptionAmount(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let prioritizedLines = lines.filter { line in
            let lower = line.lowercased()
            return lower.contains("total") ||
                lower.contains("price") ||
                lower.contains("charged") ||
                lower.contains("amount") ||
                lower.contains("subtotal") ||
                lower.contains("inclusive of vat") ||
                lower.contains("you pay") ||
                lower.contains("you were billed")
        }

        for line in prioritizedLines {
            if let amount = bestAmountString(in: line) {
                return amount
            }
        }

        for line in lines where line.contains("€") || line.contains("$") || line.contains("£") || line.contains("₺") {
            if let amount = bestAmountString(in: line) {
                return amount
            }
        }

        return nil
    }

    private func inferredSubscriptionCategory(from event: EmailScanEvent) -> SubscriptionCategory {
        let lower = "\(event.serviceName)\n\(event.normalizedText)".lowercased()
        if lower.contains("icloud") || lower.contains("dropbox") || lower.contains("drive") || lower.contains("google one") {
            return .cloud
        }
        if lower.contains("netflix") || lower.contains("spotify") || lower.contains("youtube") || lower.contains("disney") || lower.contains("apple music") {
            return .entertainment
        }
        if lower.contains("chatgpt") || lower.contains("notion") || lower.contains("adobe") || lower.contains("microsoft 365") || lower.contains("canva") {
            return .productivity
        }
        if lower.contains("gym") || lower.contains("fitness") || lower.contains("strava") {
            return .fitness
        }
        if lower.contains("bank") || lower.contains("card") || lower.contains("revolut") || lower.contains("paypal") {
            return .finance
        }
        if lower.contains("health") || lower.contains("clinic") || lower.contains("medical") {
            return .healthcare
        }
        return .utilities
    }

    private func synthesizedPayloadText(
        for event: EmailScanEvent,
        cycle: BillingCycle?,
        nextPaymentDate: Date?,
        account: EmailAccountConnectionSnapshot,
        relatedEvents: Int
    ) -> String {
        var lines: [String] = [
            "Subscription detected from email scan",
            "Service: \(event.serviceName)",
            "Mailbox account: \(account.emailAddress)"
        ]

        if event.hasPaymentEvidence {
            lines.append("Latest charge date: \(PayGuardFormatters.mediumDate.string(from: event.eventDate))")
        } else {
            lines.append("Latest subscription email date: \(PayGuardFormatters.mediumDate.string(from: event.eventDate))")
            lines.append("Status: Upcoming auto-renew subscription")
        }

        if let cycle, cycle.isRecurring {
            lines.append("Billing cycle: \(cycle.label)")
        }
        if let nextPaymentDate {
            lines.append("Next billing date: \(PayGuardFormatters.mediumDate.string(from: nextPaymentDate))")
        }
        if let amountText = event.amountText {
            lines.append("Amount: \(amountText) \(event.currencyCode ?? "EUR")")
        }

        lines.append("Detected from \(relatedEvents) matching email(s)")
        lines.append("Latest subject: \(event.subject)")
        lines.append("Latest sender: \(event.sender)")
        lines.append("Evidence preview:")
        lines.append(event.preview)

        return lines.joined(separator: "\n")
    }

    private func detectedRecurringCycle(in text: String) -> BillingCycle? {
        let lower = text.lowercased()
        if containsRecurringPattern(#"\b(one[- ]time|single payment|lifetime)\b"#, in: lower) {
            return .oneTime
        }
        if containsRecurringPattern(#"\b(quarterly|every 3 months|per 3 months|every quarter|3-month)\b"#, in: lower) ||
            containsRecurringPattern(#"(?:^|[^\d])3\s*months\b"#, in: lower) ||
            containsRecurringPattern(#"/\s*3\s*months\b"#, in: lower) {
            return .quarterly
        }
        if containsRecurringPattern(#"\b(yearly|annual|annually|per year|every year|jährlich|every 12 months)\b"#, in: lower) {
            return .yearly
        }
        if containsRecurringPattern(#"\b(weekly|per week|every week|every 7 days)\b"#, in: lower) {
            return .weekly
        }
        if containsRecurringPattern(#"\b(monthly|per month|every month|monatlich|every 30 days|every 4 weeks|billed every 4 weeks)\b|/mo\b"#, in: lower) {
            return .monthly
        }
        return nil
    }

    private func inferredServiceName(subject: String, sender: String, text: String) -> String {
        let lower = text.lowercased()
        let knownServices = [
            "Netflix", "Spotify", "YouTube", "Disney+", "Apple Music", "iCloud+", "Google One",
            "Dropbox", "Adobe", "Canva", "ChatGPT", "Notion", "Microsoft 365", "Duolingo",
            "Strava", "Headspace"
        ]
        if let known = knownServices.first(where: { lower.contains($0.lowercased()) || subject.lowercased().contains($0.lowercased()) }) {
            return known
        }

        if let choosingMatch = firstMatch(
            pattern: #"(?i)thanks for choosing\s+([A-Za-z0-9][A-Za-z0-9 &+\-]{1,40})"#,
            in: text
        ) {
            return canonicalServiceName(from: choosingMatch)
        }

        if let teamMatch = firstMatch(
            pattern: #"(?i)best regards,\s*(?:the\s+)?([A-Za-z0-9][A-Za-z0-9 &+\-]{1,40})\s+team"#,
            in: text
        ) {
            return canonicalServiceName(from: teamMatch)
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { cleanedServiceLine($0) }
            .filter { !$0.isEmpty }

        if let appStoreIndex = lines.firstIndex(where: { $0.lowercased() == "app store" || $0.lowercased().contains("app store") }) {
            let nextIndex = lines.index(after: appStoreIndex)
            if nextIndex < lines.endIndex {
                let candidates = lines[nextIndex...]
                if let productLine = candidates.first(where: isLikelyServiceNameLine) {
                    return canonicalServiceName(from: productLine)
                }
            }
        }

        if let invoiceProductLine = lines.first(where: { line in
            let lower = line.lowercased()
            return lower.contains("(monthly)") ||
                lower.contains("(yearly)") ||
                lower.contains("(weekly)") ||
                lower.contains("(3 months)") ||
                lower.contains("quarterly") ||
                (lower.contains("subscription") && !isGenericAppleInstructionLine(lower))
        }) {
            return canonicalServiceName(from: invoiceProductLine)
        }

        let subjectCandidates = subject
            .replacingOccurrences(of: "Re:", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Fwd:", with: "", options: .caseInsensitive)
            .split(separator: "-", maxSplits: 1)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let subjectCandidate = subjectCandidates.first(where: isLikelyServiceNameLine) {
            return canonicalServiceName(from: subjectCandidate)
        }

        if let line = lines.first(where: isLikelyServiceNameLine) {
            return canonicalServiceName(from: line)
        }

        let senderName = sender.split(separator: "<").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? sender
        return senderName.isEmpty ? PMLocalized("Imported subscription") : canonicalServiceName(from: senderName)
    }

    private func extractAppleRecurringInvoiceDetails(
        from text: String,
        subject: String,
        sender: String
    ) -> (serviceName: String, cycle: BillingCycle, nextBillingDate: Date?, amountText: String?)? {
        let subjectLower = subject.lowercased()
        let senderLower = sender.lowercased()
        let textLower = text.lowercased()

        let looksLikeAppleRecurringMessage =
            (subjectLower.contains("invoice") || subjectLower.contains("receipt") || subjectLower.contains("subscription renewal")) &&
            (senderLower.contains("apple") || senderLower.contains("email.apple.com") || textLower.contains("apple account") || textLower.contains("app store"))
        guard looksLikeAppleRecurringMessage else { return nil }

        let lines = text
            .components(separatedBy: .newlines)
            .map { cleanedServiceLine($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let renewIndex = lines.firstIndex(where: { $0.lowercased().contains("renews") || $0.lowercased().contains("starting from") })
        let planIndex = lines.firstIndex(where: { containsApplePlanDescriptor($0) })
            ?? renewIndex.flatMap { index in
                guard index > 0 else { return nil }
                let priorLine = lines[index - 1]
                return containsApplePlanDescriptor(priorLine) || isLikelyServiceNameLine(canonicalServiceName(from: priorLine)) ? (index - 1) : nil
            }

        let planLine = planIndex.map { lines[$0] }
        let cycle = planLine.flatMap { detectedRecurringCycle(in: $0) } ?? detectedRecurringCycle(in: text)
        guard let cycle, cycle.isRecurring else { return nil }

        let serviceName: String
        if let planLine {
            serviceName = canonicalServiceName(from: planLine)
        } else if let anchoredServiceName = appleSubscriptionServiceName(from: lines) {
            serviceName = anchoredServiceName
        } else {
            let fallbackName = inferredServiceName(subject: subject, sender: sender, text: text)
            let lowerFallback = fallbackName.lowercased()
            guard lowerFallback != "subscription renewal",
                  lowerFallback != "your subscription renewal",
                  lowerFallback != "apple",
                  lowerFallback != "app store" else {
                return nil
            }
            serviceName = fallbackName
        }

        let anchorIndex = planIndex ?? lines.firstIndex(where: { line in
            let lower = line.lowercased()
            return lower.contains("subscription renewal") || lower.contains("app store") || lower.contains("renews") || lower.contains("starting from")
        }) ?? 0
        let nearbyLines = Array(lines[anchorIndex..<min(anchorIndex + 6, lines.count)]).joined(separator: "\n")
        let renewDate = detectedDate(
            in: nearbyLines,
            matchingAnyOf: ["renews", "next billing", "next payment", "starting from", "continue for"],
            preferFuture: true
        ) ?? detectedDate(
            in: text,
            matchingAnyOf: ["renews", "next billing", "next payment", "will renew on", "subscription renewal", "starting from", "continue for"],
            preferFuture: true
        ) ?? bestDateCandidate(in: nearbyLines, preferFuture: true)

        let amountWindowStart = max(anchorIndex - 1, 0)
        let amountWindowEnd = min(anchorIndex + 8, lines.count)
        let amountWindow = Array(lines[amountWindowStart..<amountWindowEnd]).joined(separator: "\n")
        let amountText = detectedSubscriptionAmount(in: amountWindow) ?? detectedSubscriptionAmount(in: text)

        return (
            serviceName: serviceName,
            cycle: cycle,
            nextBillingDate: renewDate,
            amountText: amountText
        )
    }

    private func appleSubscriptionServiceName(from lines: [String]) -> String? {
        let genericNames = Set([
            "subscription renewal",
            "your subscription renewal",
            "app store",
            "apple"
        ])

        let explicitRecurringLine = lines.first(where: { line in
            let cleaned = canonicalServiceName(from: line)
            return containsApplePlanDescriptor(line) &&
                isLikelyServiceNameLine(cleaned) &&
                !genericNames.contains(cleaned.lowercased())
        })
        if let explicitRecurringLine {
            return canonicalServiceName(from: explicitRecurringLine)
        }

        let anchorPhrases = ["subscription renewal", "app store"]
        for index in lines.indices {
            let lower = lines[index].lowercased()
            guard anchorPhrases.contains(where: { lower.contains($0) }) else { continue }
            let searchWindow = lines.dropFirst(index + 1).prefix(6)
            if let candidate = searchWindow.first(where: { line in
                let cleaned = canonicalServiceName(from: line)
                return isLikelyServiceNameLine(cleaned) && !genericNames.contains(cleaned.lowercased())
            }) {
                return canonicalServiceName(from: candidate)
            }
        }

        if let recurringLine = lines.first(where: { line in
            containsApplePlanDescriptor(line)
        }) {
            let cleaned = canonicalServiceName(from: recurringLine)
            if !genericNames.contains(cleaned.lowercased()) {
                return cleaned
            }
        }

        if let renewIndex = lines.firstIndex(where: { $0.lowercased().contains("renews") || $0.lowercased().contains("starting from") }),
           renewIndex > 0 {
            let searchStart = max(renewIndex - 3, 0)
            let candidates = lines[searchStart..<renewIndex].reversed()
            if let candidate = candidates
                .map(canonicalServiceName(from:))
                .first(where: { candidate in
                    isLikelyServiceNameLine(candidate) && !genericNames.contains(candidate.lowercased())
                }) {
                return candidate
            }
        }

        return nil
    }

    private func isLikelyServiceNameLine(_ line: String) -> Bool {
        guard (2...42).contains(line.count),
              line.rangeOfCharacter(from: .letters) != nil else {
            return false
        }

        let lower = line.lowercased()
        let blockedFragments = [
            "invoice", "receipt", "report a problem", "subtotal", "vat", "apple account",
            "order id", "document no", "invoice date", "total", "app store", "payment",
            "fetch", "body[]", "return-path", "original-recipient", "received:", "support team",
            "ticket", "tuition", "mailbox account", "latest charge date", "latest subject", "latest sender",
            "subscription renewal", "your subscription renewal", "creator studio", "apple developer",
            "submission is complete", "turn on renewal receipt emails", "purchase history",
            "manage subscriptions", "view your receipts", "get help with subscriptions"
        ]
        return !blockedFragments.contains(where: { lower.contains($0) })
    }

    private func cleanedServiceLine(_ line: String) -> String {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^\* \d+ FETCH \(UID \d+ BODY\[\] \{\d+\}\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "deviceName", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "purchaseDateTime", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func canonicalServiceName(from value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = normalized.range(of: #"\s*\((monthly|yearly|weekly|annual|(?:\d+\s+months?)).*$"#, options: [.regularExpression, .caseInsensitive]) {
            normalized.removeSubrange(range)
        }
        if let range = normalized.range(of: #"\s+(monthly|yearly|weekly|annual|quarterly)\b.*$"#, options: [.regularExpression, .caseInsensitive]) {
            normalized.removeSubrange(range)
        }

        if let colonIndex = normalized.firstIndex(of: ":") {
            normalized = String(normalized[..<colonIndex])
        }

        let blockedSuffixes = ["pro", "premium", "subscription", "membership"]
        let components = normalized.split(separator: " ").map(String.init)
        if components.count >= 2,
           blockedSuffixes.contains(components.last?.lowercased() ?? "") {
            normalized = components.dropLast().joined(separator: " ")
        }

        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("* ") {
            return PMLocalized("Imported subscription")
        }
        return normalized.isEmpty ? PMLocalized("Imported subscription") : normalized
    }

    private func containsApplePlanDescriptor(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard !isGenericAppleInstructionLine(lower) else { return false }
        if lower.contains("(monthly)") ||
            lower.contains("(yearly)") ||
            lower.contains("(weekly)") ||
            lower.contains("(annual)") ||
            lower.contains("(3 months)") ||
            lower.contains("quarterly") ||
            lower.contains("/3 months") {
            return true
        }
        return lower.range(of: #"\b(monthly|yearly|weekly|annual)\b"#, options: .regularExpression) != nil &&
            !lower.contains("turn on renewal receipt emails")
    }

    private func isGenericAppleInstructionLine(_ lower: String) -> Bool {
        [
            "you can view your receipts",
            "turn on renewal receipt emails",
            "get help with subscriptions",
            "manage subscriptions",
            "purchase history",
            "view your account information",
            "visit apple support"
        ].contains(where: { lower.contains($0) })
    }

    private func isNoisePreviewLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lower = trimmed.lowercased()
        let noisePatterns = [
            #"^\* \d+ fetch \(uid \d+ body\[\]"#,
            #"^a\d+\s+ok uid fetch completed$"#,
            #"^return-path:"#,
            #"^original-recipient:"#,
            #"^received:"#,
            #"^mime-version:"#,
            #"^content-type:"#,
            #"^content-transfer-encoding:"#,
            #"^x-[\w-]+:"#,
            #"^dkim-signature:"#,
            #"^arc-[\w-]+:"#,
            #"^authentication-results:"#,
            #"^message-id:"#,
            #"^references:"#,
            #"^in-reply-to:"#,
            #"^>)"#,
            #"^\)$"#
        ]
        return noisePatterns.contains { pattern in
            lower.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func containsRecurringPattern(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else { return nil }
        return nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func detectedDate(
        in text: String,
        matchingAnyOf phrases: [String],
        preferFuture: Bool
    ) -> Date? {
        let lines = text.components(separatedBy: .newlines)
        for index in lines.indices {
            let lower = lines[index].lowercased()
            guard phrases.contains(where: { lower.contains($0) }) else { continue }
            let snippetLines = [lines[index]] + Array(lines.dropFirst(index + 1).prefix(2))
            let snippet = snippetLines.joined(separator: "\n")
            if let date = bestDateCandidate(in: snippet, preferFuture: preferFuture) {
                return date
            }
        }

        return nil
    }

    private func bestDateCandidate(in text: String, preferFuture: Bool) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        var candidates = matches.compactMap(\.date)
        candidates.append(contentsOf: manuallyDetectedDates(in: text))
        candidates = Array(Set(candidates.map { $0.timeIntervalSinceReferenceDate })).compactMap(Date.init(timeIntervalSinceReferenceDate:))

        if preferFuture {
            return candidates
                .filter { $0 >= .now.startOfDay }
                .sorted()
                .first
        }

        return candidates
            .filter { $0 <= .now }
            .sorted(by: >)
            .first
    }

    private func manuallyDetectedDates(in text: String) -> [Date] {
        let patterns = [
            #"\b\d{1,2}\.\s+[A-Za-z]+\s+\d{4}\b"#,
            #"\b\d{1,2}\s+[A-Za-z]+\s+\d{4}\b"#
        ]
        let formatters: [DateFormatter] = {
            let locales = ["en_US_POSIX", "en_GB", "de_DE"]
            let formats = ["d. MMMM yyyy", "d MMMM yyyy", "dd. MMMM yyyy", "dd MMMM yyyy"]
            return locales.flatMap { localeID in
                formats.map { format in
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: localeID)
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = format
                    return formatter
                }
            }
        }()

        var results: [Date] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: nsRange) {
                guard let range = Range(match.range, in: text) else { continue }
                let candidate = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                for formatter in formatters {
                    if let date = formatter.date(from: candidate) {
                        results.append(date)
                        break
                    }
                }
            }
        }
        return results
    }

    private func parsedHeaderDate(from text: String) -> Date? {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm Z",
            "EEE, dd MMM yyyy HH:mm Z"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }

        return nil
    }
}

private struct EmailScanEvent {
    let serviceName: String
    let mailbox: String
    let subject: String
    let sender: String
    let dateText: String
    let preview: String
    let normalizedText: String
    let receivedAt: Date?
    let eventDate: Date
    let nextBillingDate: Date?
    let amountText: String?
    let currencyCode: String?
    let explicitCycle: BillingCycle?
    let isCancellation: Bool
    let hasPaymentEvidence: Bool
    let hasRenewalCommitment: Bool
    let confidence: Double

    var serviceKey: String {
        serviceName.normalizedLookupKey
    }

    var messageKey: String {
        "\(mailbox.lowercased())|\(subject.lowercased())|\(sender.lowercased())|\(eventDate.timeIntervalSince1970)"
    }
}

private final class SafeContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume()
    }

    func resumeOnce(_ continuation: CheckedContinuation<Void, Error>, throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(throwing: error)
    }
}

private struct IMAPResponse {
    let tag: String
    let raw: String

    var isOK: Bool {
        raw.range(of: "\(tag) OK", options: [.caseInsensitive]) != nil
    }
}

private final class IMAPClient {
    private let host: String
    private let port: Int
    private let useTLS: Bool
    private var connection: NWConnection?
    private var tagCounter = 1

    init(host: String, port: Int, useTLS: Bool) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }

    func connect() async throws {
        let parameters: NWParameters = useTLS ? .tls : .tcp
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 993, using: parameters)
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = SafeContinuationGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resumeOnce(continuation)
                case .failed(let error):
                    gate.resumeOnce(continuation, throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }

        _ = try await readUntilLineContaining(nil, timeoutNanoseconds: 5_000_000_000)
    }

    func disconnect() async throws {
        if let response = try? await send("LOGOUT") {
            _ = response.raw
        }
        connection?.cancel()
        connection = nil
    }

    func login(username: String, password: String) async throws -> IMAPResponse {
        try await send("LOGIN \"\(imapEscaped(username))\" \"\(imapEscaped(password))\"")
    }

    func selectMailbox(_ mailbox: String) async throws -> IMAPResponse {
        try await send("SELECT \"\(imapEscaped(mailbox))\"")
    }

    func listMailboxes() async throws -> IMAPResponse {
        try await send("LIST \"\" \"*\"", timeoutNanoseconds: 10_000_000_000)
    }

    func uidSearch(criteria: String) async throws -> IMAPResponse {
        try await send("UID SEARCH \(criteria)", timeoutNanoseconds: 10_000_000_000)
    }

    func uidFetchMessage(uid: Int, byteLimit: Int) async throws -> IMAPResponse {
        try await send("UID FETCH \(uid) (BODY.PEEK[]<0.\(byteLimit)>)", timeoutNanoseconds: 8_000_000_000)
    }

    private func send(_ command: String, timeoutNanoseconds: UInt64 = 6_000_000_000) async throws -> IMAPResponse {
        guard let connection else { throw EmailAutoDiscoveryError.connectionFailed }
        let tag = nextTag()
        let line = "\(tag) \(command)\r\n"
        guard let data = line.data(using: .utf8) else { throw EmailAutoDiscoveryError.connectionFailed }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }

        let raw = try await readUntilLineContaining(tag, timeoutNanoseconds: timeoutNanoseconds)
        return IMAPResponse(tag: tag, raw: raw)
    }

    private func nextTag() -> String {
        let tag = String(format: "A%04d", tagCounter)
        tagCounter += 1
        return tag
    }

    private func imapEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func readUntilLineContaining(_ tag: String?, timeoutNanoseconds: UInt64) async throws -> String {
        guard let connection else { throw EmailAutoDiscoveryError.connectionFailed }
        var buffer = Data()
        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000.0)

        while Date() < deadline {
            let data = try await receiveChunk(from: connection)
            if data.isEmpty { continue }
            buffer.append(data)
            let raw = String(data: buffer, encoding: .utf8) ?? String(decoding: buffer, as: UTF8.self)
            if let tag {
                if raw.range(of: "\r\n\(tag) ") != nil || raw.hasPrefix("\(tag) ") || raw.range(of: "\n\(tag) ") != nil {
                    return raw
                }
            } else if raw.contains("\n") || raw.contains("\r\n") {
                return raw
            }
        }
        throw EmailAutoDiscoveryError.connectionFailed
    }

    private func receiveChunk(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: Data())
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}
