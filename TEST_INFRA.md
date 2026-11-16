# E2E Test Infra: iOS Messenger Client (MSNP18 / WLM 2009)

## Test Philosophy
- **Opaque-box & Requirement-driven**: Tests derive strictly from user requirements (`ORIGINAL_REQUEST.md`), MSNP18 specifications, and WLM 2009 behavioral definitions rather than implementation internals.
- **Methodology**:
  - **Category-Partition**: Equivalence-class partitioning of valid/invalid inputs across all 7 core feature domains.
  - **Boundary Value Analysis (BVA)**: Stress testing limits (0 items, 1 item, max limits, timeout edges, cooldown window boundaries).
  - **Pairwise Combinatorial Testing**: Systematically exercising major cross-feature combinations to uncover concurrency and state interaction bugs.
  - **Real-World Application Workload Testing**: Multi-step user journey scenarios replicating authentic messenger usage.

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 (Happy Path) | Tier 2 (Boundary & Corner) | Tier 3 (Cross-Feature) |
|---|---------|---------------------|:-------------------:|:--------------------------:|:----------------------:|
| 1 | Server Presets & Endpoints | ORIGINAL_REQUEST §R1 | ≥ 5 | ≥ 5 | ✓ |
| 2 | Auth Flow & Handshake | ORIGINAL_REQUEST §R1 | ≥ 5 | ≥ 5 | ✓ |
| 3 | Skin & Theme Loading | ORIGINAL_REQUEST §R2 | ≥ 5 | ≥ 5 | ✓ |
| 4 | Contact Groups & Presence | ORIGINAL_REQUEST §R3 | ≥ 5 | ≥ 5 | ✓ |
| 5 | Chat Messaging (1:1 & Group) | ORIGINAL_REQUEST §R3 | ≥ 5 | ≥ 5 | ✓ |
| 6 | Nudges (Trilli) | ORIGINAL_REQUEST §R3 | ≥ 5 | ≥ 5 | ✓ |
| 7 | Winks Interactive System | ORIGINAL_REQUEST §R3 | ≥ 5 | ≥ 5 | ✓ |

## Test Architecture
- **Test Runner**: Swift Package Manager (`swift test`) and Xcode XCTest (`xcodebuild test`).
- **Pass/Fail Semantics**: All test suites must execute with exit code 0; zero test failures, zero unexpected assertions, zero unhandled exceptions.
- **Directory Layout**:
  - `Tests/MsngrCoreTests/`: Data model encoding/decoding, MSNObject parsing, Plus! formatting, payload codecs.
  - `Tests/MsngrProtocolTests/`: MSNP18 framing, command parsing/serialization, SOAP RST request generation, RPS 3DES proof derivation.
  - `Tests/MsngrUITests/`: SkinManager, NudgeShakeEngine displacement deltas, ViewModels (`SessionViewModel`, `ChatViewModel`, `WinkManager`).
  - `Tests/MsngrIntegrationTests/`:
    - `Tier1_FeatureCoverageTests.swift`: Happy-path feature coverage (≥5 tests per feature).
    - `Tier2_BoundaryCornerTests.swift`: Negative testing, boundary values, network timeouts, malformed payloads (≥5 tests per feature).
    - `Tier3_CrossFeatureTests.swift`: Pairwise feature interactions and state switching.
    - `Tier4_RealWorldScenariosTests.swift`: End-to-end user journeys and multi-feature workflows.
    - `MockTransport/`: Protocol simulation harness (`MockSocketStream`, `MockNotificationServer`, `MockSwitchboard`).

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Full Sign-In to Sign-Out Lifecycle | F1 (Preset), F2 (Auth), F4 (Contacts), F5 (Chat) | High |
| 2 | Active 1-on-1 Chat with Media (Nudge & Wink) | F4 (Presence), F5 (Chat), F6 (Nudge), F7 (Wink) | High |
| 3 | Multi-User Circle/Group Conversation | F4 (Groups), F5 (Group Chat), F6 (Nudge), F7 (Wink) | High |
| 4 | Mid-Session Theming & Preset Reconfiguration | F1 (Preset), F3 (Skin/Theme), F5 (Chat) | Medium |
| 5 | Network Interruption, Socket Reconnect & Roster Resync | F1 (Preset), F2 (Handshake), F4 (Contacts), F5 (Chat) | High |

## Coverage Thresholds
- **Tier 1**: ≥ 5 tests per feature (7 features × 5 = ≥ 35 test cases)
- **Tier 2**: ≥ 5 tests per feature (7 features × 5 = ≥ 35 test cases)
- **Tier 3**: Pairwise coverage of major feature interactions (≥ 7 combination test cases)
- **Tier 4**: ≥ 5 realistic application-level scenarios
- **Total Minimum Test Count**: ≥ 82 test cases across integration and unit suites.
