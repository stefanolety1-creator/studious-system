import SwiftUI
import MsngrCore
import MsngrProtocol
import MsngrUI

@main
public struct MsngrApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup("Windows Live Messenger") {
            RootContentView()
        }
    }
}
