import XCTest
import SwiftUI
@testable import MsngrCore
@testable import MsngrUI

final class SkinManagerTests: XCTestCase {

    // MARK: - Active Skin Color Mapping Tests

    func test_skinManager_activeSkinColorMapping() {
        // WLM 2009 Light Aero
        let lightSkin = AeroSkin.wlm2009Light
        XCTAssertEqual(lightSkin.rawValue, "WLM 2009 Aero (Light)")
        XCTAssertEqual(lightSkin.primaryColor, Color.wlmPrimary)
        XCTAssertEqual(lightSkin.windowBackgroundColor, Color.wlmWindowBackground)
        XCTAssertFalse(lightSkin.isDark, "WLM 2009 Light skin must not be dark mode")

        // WLM Night Aero (Dark)
        let darkSkin = AeroSkin.wlm2009Night
        XCTAssertEqual(darkSkin.rawValue, "WLM Night Aero (Dark)")
        XCTAssertEqual(darkSkin.primaryColor, Color.wlmNightPrimary)
        XCTAssertEqual(darkSkin.windowBackgroundColor, Color.wlmNightBackground)
        XCTAssertTrue(darkSkin.isDark, "WLM Night Aero skin must be dark mode")

        // MSN 7.5 Classic
        let retroSkin = AeroSkin.msn75Classic
        XCTAssertEqual(retroSkin.rawValue, "MSN Messenger 7.5")
        XCTAssertEqual(retroSkin.primaryColor, Color.msn75Primary)
        XCTAssertEqual(retroSkin.windowBackgroundColor, Color.msn75Background)
        XCTAssertFalse(retroSkin.isDark, "MSN 7.5 skin must not be dark mode")
    }

    // MARK: - Scene Gradient Generation Tests

    func test_skinManager_sceneGradientGeneration() {
        let allScenes = WlmScene.allCases
        XCTAssertGreaterThanOrEqual(allScenes.count, 7, "WlmScene must provide at least 7 authentic scenes")

        for scene in allScenes {
            // Verify scene title is non-empty
            XCTAssertFalse(scene.rawValue.isEmpty, "Scene rawValue must not be empty")

            // Verify headerGradient is instantiated
            let gradient = scene.headerGradient
            _ = gradient // Ensure valid instantiation

            // Verify dark text flag: Mesmerizing White requires dark text for readability
            if scene == .mesmerizingWhite {
                XCTAssertTrue(scene.isDarkText, "Mesmerizing White scene requires dark text")
            } else {
                XCTAssertFalse(scene.isDarkText, "\(scene.rawValue) scene expects light/white text")
            }
        }
    }

    // MARK: - Dark Mode Detection Tests

    func test_skinManager_darkModeDetection() {
        for skin in AeroSkin.allCases {
            switch skin {
            case .wlm2009Night:
                XCTAssertTrue(skin.isDark, "Night Aero must report isDark == true")
            case .wlm2009Light, .msn75Classic:
                XCTAssertFalse(skin.isDark, "\(skin.rawValue) must report isDark == false")
            }
        }

        // Atmospheric backdrop gradients selection
        let lightAtmosphere = LinearGradient.wlmAtmosphereLight
        let darkAtmosphere = LinearGradient.wlmAtmosphereDark
        _ = lightAtmosphere
        _ = darkAtmosphere
    }
}
