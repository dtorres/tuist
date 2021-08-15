import Foundation
import TuistCore
import TuistGraph

final class CacheWorkspaceMapper: WorkspaceMapping { // swiftlint:disable:this type_name
    private let targetsToFilter: [Target]

    init(targetsToFilter: [Target]) {
        self.targetsToFilter = targetsToFilter
    }

    func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        let schemes: [Scheme] = Platform.allCases.flatMap { platform in
            scheme(
                platform: platform,
                workspace: workspace
            )
        }

        var workspace = workspace
        workspace.workspace.schemes.append(contentsOf: schemes)
        return (workspace, [])
    }

    // MARK: - Helpers

    private func scheme(
        platform: Platform,
        workspace: WorkspaceWithProjects
    ) -> [Scheme] {
        let projectsWithTargets = workspace
            .projects
            .flatMap { project in project.targets.map { (project, $0) } }
            .filter { $0.1.platform == platform }
            .filter { _, target in targetsToFilter.contains { $0.name == target.name } }

        let bundleTargets = projectsWithTargets
            .filter { $0.1.product == .bundle }

        let frameworksTargets = projectsWithTargets
            .filter { $0.1.product.isFramework }

        let bundleTargetReferences = bundleTargets
            .map { TargetReference(projectPath: $0.0.path, name: $0.1.name) }
            .sorted(by: { $0.name < $1.name })
        let frameworksTargetReferences = frameworksTargets
            .map { TargetReference(projectPath: $0.0.path, name: $0.1.name) }
            .sorted(by: { $0.name < $1.name })

        return [
            Scheme(
                name: "ProjectCache-Bundles-\(platform.caseValue)",
                shared: true,
                buildAction: BuildAction(targets: bundleTargetReferences)
            ),
            Scheme(
                name: "ProjectCache-Frameworks-\(platform.caseValue)",
                shared: true,
                buildAction: BuildAction(targets: frameworksTargetReferences)
            ),
        ]
    }
}
