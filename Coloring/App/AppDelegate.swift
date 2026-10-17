import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

/// UIKit owns the window so the root controller can claim the screen edges: SwiftUI on
/// iPadOS 15 has no way to hide the home indicator or defer edge swipes, and a child's
/// stray swipe from the bottom shouldn't throw them out of their drawing.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var model: AppModel?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let model = AppModel(store: ArtworkStore(root: AppModel.storeRoot()))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = RootHostingController(rootView: RootView(model: model))
        window.makeKeyAndVisible()
        self.model = model
        self.window = window
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        guard let model else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "save artwork")
        Task { @MainActor in
            await model.saveOpenPage()
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}

final class RootHostingController: UIHostingController<RootView> {
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersStatusBarHidden: Bool { true }
}
