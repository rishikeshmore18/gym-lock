import SwiftUI
import UIKit

/// Keeps the edge swipe back working on pages that hide the navigation bar
/// to draw their own glass header.
///
/// UIKit switches the interactive pop off whenever the bar is hidden, so a
/// page with a custom back button would otherwise lose the gesture people
/// reach for first. Drop this into the page's background; it installs one
/// delegate per navigation controller that allows the swipe only when there
/// is something to go back to and no transition is already running. That
/// guard is what stops the well-known freeze from swiping on a root page.
struct InteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) {}

    final class Probe: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            install()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }

        private func install() {
            guard let navigation = navigationController,
                  let pop = navigation.interactivePopGestureRecognizer
            else { return }
            let delegate = PopGestureDelegate.attached(to: navigation)
            if pop.delegate !== delegate { pop.delegate = delegate }
            pop.isEnabled = true
        }
    }
}

/// One per navigation controller, owned by it, so it can never dangle.
final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private static var associationKey: UInt8 = 0

    private weak var navigation: UINavigationController?

    private init(navigation: UINavigationController) {
        self.navigation = navigation
    }

    static func attached(to navigation: UINavigationController) -> PopGestureDelegate {
        if let existing = objc_getAssociatedObject(navigation, &associationKey) as? PopGestureDelegate {
            return existing
        }
        let created = PopGestureDelegate(navigation: navigation)
        objc_setAssociatedObject(navigation, &associationKey, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return created
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation else { return false }
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
    }
}
