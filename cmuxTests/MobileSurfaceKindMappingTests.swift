import CMUXMobileCore
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite struct MobileSurfaceKindMappingTests {
    /// The canonical PanelType -> wire-kind vocabulary. Both mapping
    /// functions must produce these exact strings; asserting only parity
    /// would pass when both drift to the same wrong value.
    private static let canonicalKinds: [PanelType: String] = [
        .terminal: "terminal",
        .browser: "browser",
        .markdown: "markdown",
        .filePreview: "filePreview",
        .rightSidebarTool: "rightSidebarTool",
        .customSidebar: "customSidebar",
        .agentSession: "agentSession",
        .project: "project",
        .extensionBrowser: "extensionBrowser",
        .workspaceTodo: "todo",
        .cloudVMLoading: "cloudVMLoading",
    ]

    @Test func everyPanelTypeMapsToItsCanonicalWireKind() throws {
        #expect(Self.canonicalKinds.count == PanelType.allCases.count)
        let controller = TerminalController.shared
        for panelType in PanelType.allCases {
            let canonical = try #require(
                Self.canonicalKinds[panelType],
                "no canonical kind declared for \(panelType.rawValue)"
            )
            #expect(controller.mobileSurfaceKind(for: panelType).rawValue == canonical)
            #expect(Workspace.surfaceKind(for: panelType) == canonical)
        }
    }
}

@MainActor
@Suite(.serialized) struct MobilePanelArtifactTests {
    @Test func statReadsTheFileDisplayedByALiveMarkdownPanel() async throws {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-mobile-markdown-artifact-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("README.md")
        let markdown = "# Mobile preview\n\nLoaded from the Mac.\n"
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        let manager = TabManager()
        let workspace = manager.addWorkspace(select: true, eagerLoadTerminal: false)
        let paneID = try #require(workspace.bonsplitController.allPaneIds.first)
        let panel = try #require(workspace.newMarkdownSurface(
            inPane: paneID,
            filePath: fileURL.path,
            focus: false
        ))
        let controller = TerminalController.shared
        controller.setActiveTabManager(manager)
        defer {
            manager.closeWorkspace(workspace, recordHistory: false)
            controller.setActiveTabManager(nil)
        }

        _ = controller.mobileSurfaceDescriptors(in: workspace)
        let result = await controller.v2MobilePanelArtifactStat(params: [
            "workspace_id": workspace.id.uuidString,
            "surface_id": panel.id.uuidString,
            "path": fileURL.path,
        ])

        guard case .ok(let rawPayload) = result,
              let payload = rawPayload as? [String: Any] else {
            Issue.record("Expected the live Markdown panel artifact stat to succeed, got \(result)")
            return
        }
        #expect((payload["size"] as? NSNumber)?.int64Value == Int64(markdown.utf8.count))
    }
}
