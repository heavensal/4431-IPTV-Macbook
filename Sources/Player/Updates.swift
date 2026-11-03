import SwiftUI
import Sparkle

@MainActor final class Updates: ObservableObject {
    private let controller = SPUStandardUpdaterController(startingUpdater:true,updaterDelegate:nil,userDriverDelegate:nil)
    func check() { controller.checkForUpdates(nil) }
}
