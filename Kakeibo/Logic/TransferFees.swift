import Foundation

/// A transfer with a fee (an ATM withdrawal, a bank transfer). The fee is either taken from the amount
/// you type (¥10,000 leaves, ¥9,780 arrives) or added on top of it (¥10,000 arrives, ¥10,220 leaves).
/// Either way the entry stores what leaves the source as `amount`, plus the fee.
struct TransferAmounts: Equatable {
    /// What leaves the source account (the entry's `amount`).
    let sent: Int
    let fee: Int

    /// What reaches the destination.
    var received: Int { sent - fee }

    /// `typed` is what leaves the source, or with `onTop` what arrives.
    init(typed: Int, fee: Int, onTop: Bool) {
        let fee = max(fee, 0)
        self.fee = fee
        sent = onTop ? typed + fee : typed
    }

    /// Something has to arrive: the fee can't eat the whole amount.
    var isValid: Bool { sent > 0 && received > 0 }

    /// The number the editor shows for a saved transfer: what leaves, or what arrives if the fee was
    /// entered on top.
    static func typed(for entry: Entry) -> Int {
        entry.feePaid > 0 && entry.transferFeeOnTop ? entry.received : entry.amount
    }
}
