import Foundation

/// The phrases that roll like a lottery machine beside the fixed word "Problem".
enum ProblemCycle {
    /// Ordered exactly as the approved onboarding copy specifies.
    static let phrases: [String] = [
        "Decision fatigue",
        "Phone interception",
        "First-miss spiral",
        "Poor sleep",
        "No real accountability",
        "Vague goals",
        "Fatigue at transition moment",
        "Habit not automatic yet",
        "Restart fatigue",
        "Rigid scheduling",
        "Genuine scheduling conflict",
        "Environmental intimidation",
    ]

    /// A single node on the cyclical loop diagram.
    struct Node: Identifiable, Hashable {
        let id: Int
        /// Short label used around the ring, where space is tight.
        let label: String
        /// The long-form phrase this node corresponds to in `phrases`.
        let phrase: String
    }

    /// Twelve nodes arranged clockwise starting from the top of the ring,
    /// mirroring the approved loop diagram.
    static let nodes: [Node] = [
        Node(id: 0, label: "Decision\nfatigue", phrase: "Decision fatigue"),
        Node(id: 1, label: "Phone\npickup", phrase: "Phone interception"),
        Node(id: 2, label: "Miss\nspiral", phrase: "First-miss spiral"),
        Node(id: 3, label: "Bad\nsleep", phrase: "Poor sleep"),
        Node(id: 4, label: "No\npartner", phrase: "No real accountability"),
        Node(id: 5, label: "Vague\ngoals", phrase: "Vague goals"),
        Node(id: 6, label: "Evening\nfatigue", phrase: "Fatigue at transition moment"),
        Node(id: 7, label: "Not\nautomatic", phrase: "Habit not automatic yet"),
        Node(id: 8, label: "Restart\nfatigue", phrase: "Restart fatigue"),
        Node(id: 9, label: "Rigid\nrules", phrase: "Rigid scheduling"),
        Node(id: 10, label: "Real\nconflict", phrase: "Genuine scheduling conflict"),
        Node(id: 11, label: "Gym\nintimidation", phrase: "Environmental intimidation"),
    ]

    /// Index of the ring node that matches a rolling phrase, if any.
    static func nodeIndex(matching phrase: String) -> Int? {
        nodes.firstIndex { $0.phrase == phrase }
    }
}
