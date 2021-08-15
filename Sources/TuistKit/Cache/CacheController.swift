import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCloud
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistSupport

/// A provider that concatenates the default mappers, to the mapper that adds the build phase
/// to locate the built products directory.
class CacheControllerProjectMapperProvider: ProjectMapperProviding {
    fileprivate let contentHasher: ContentHashing
    init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    func mapper(config: Config) -> ProjectMapping {
        let defaultProjectMapperProvider = ProjectMapperProvider(contentHasher: contentHasher)
        let defaultMapper = defaultProjectMapperProvider.mapper(
            config: config
        )
        return SequentialProjectMapper(mappers: [defaultMapper])
    }
}

protocol CacheControllerProjectGeneratorProviding {
    /// Returns an instance of the project generator that should be used to generate the projects for caching.
    /// - Returns: An instance of the project generator.
    func generator() -> Generating

    /// Returns an instance of the project generator that should be used to generate the projects for caching.
    /// - Parameter targetsToFilter: Targets to be filtered
    /// - Returns: An instance of the project generator.
    func generator(targetsToFilter: [Target]) -> Generating
}

/// A provider that returns the project generator that should be used by the cache controller.
class CacheControllerProjectGeneratorProvider: CacheControllerProjectGeneratorProviding {
    private let contentHasher: ContentHashing

    init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    func generator() -> Generating {
        return generator(targetsToFilter: [])
    }

    func generator(targetsToFilter: [Target]) -> Generating {
        let contentHasher = CacheContentHasher()
        let projectMapperProvider = CacheControllerProjectMapperProvider(contentHasher: contentHasher)
        let workspaceMapperProvider = WorkspaceMapperProvider(projectMapperProvider: projectMapperProvider)
        let cacheWorkspaceMapperProvider = CacheWorkspaceMapperProvider(workspaceMapperProvider: workspaceMapperProvider, targetsToFilter: targetsToFilter)
        return Generator(
            projectMapperProvider: projectMapperProvider,
            graphMapperProvider: GraphMapperProvider(),
            workspaceMapperProvider: cacheWorkspaceMapperProvider,
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
}

protocol CacheControlling {
    /// Caches the cacheable targets that are part of the workspace or project at the given path.
    /// - Parameters:
    ///   - path: Path to the directory that contains a workspace or a project.
    ///   - cacheProfile: The caching profile.
    ///   - targets: If present, a list of target to build.
    func cache(path: AbsolutePath, cacheProfile: TuistGraph.Cache.Profile, targetsToFilter: [String]) throws
}

final class CacheController: CacheControlling {
    /// Project generator provider.
    let projectGeneratorProvider: CacheControllerProjectGeneratorProviding

    /// Utility to build the (xc)frameworks.
    private let artifactBuilder: CacheArtifactBuilding

    private let bundleArtifactBuilder: CacheArtifactBuilding

    /// Cache graph content hasher.
    private let cacheGraphContentHasher: CacheGraphContentHashing

    /// Cache.
    private let cache: CacheStoring

    /// Cache graph linter.
    private let cacheGraphLinter: CacheGraphLinting

    convenience init(cache: CacheStoring,
                     artifactBuilder: CacheArtifactBuilding,
                     bundleArtifactBuilder: CacheArtifactBuilding,
                     contentHasher: ContentHashing)
    {
        self.init(
            cache: cache,
            artifactBuilder: artifactBuilder,
            bundleArtifactBuilder: bundleArtifactBuilder,
            projectGeneratorProvider: CacheControllerProjectGeneratorProvider(contentHasher: contentHasher),
            cacheGraphContentHasher: CacheGraphContentHasher(contentHasher: contentHasher),
            cacheGraphLinter: CacheGraphLinter()
        )
    }

    init(cache: CacheStoring,
         artifactBuilder: CacheArtifactBuilding,
         bundleArtifactBuilder: CacheArtifactBuilding,
         projectGeneratorProvider: CacheControllerProjectGeneratorProviding,
         cacheGraphContentHasher: CacheGraphContentHashing,
         cacheGraphLinter: CacheGraphLinting)
    {
        self.cache = cache
        self.projectGeneratorProvider = projectGeneratorProvider
        self.artifactBuilder = artifactBuilder
        self.bundleArtifactBuilder = bundleArtifactBuilder
        self.cacheGraphContentHasher = cacheGraphContentHasher
        self.cacheGraphLinter = cacheGraphLinter
    }

    func cache(path: AbsolutePath, cacheProfile: TuistGraph.Cache.Profile, targetsToFilter: [String]) throws {
        let generator = projectGeneratorProvider.generator()
        let (_, graph) = try generator.generateWithGraph(path: path, projectOnly: false)

        // Lint
        cacheGraphLinter.lint(graph: graph)

        // Hash
        logger.notice("Hashing cacheable targets")

        let hashesByTargetToBeCached = try makeHashesByTargetToBeCached(
            for: graph,
            cacheProfile: cacheProfile,
            targetsToFilter: targetsToFilter
        )

        logger.notice("Filtering cacheable targets")

        let updatedGenerator = projectGeneratorProvider.generator(
            targetsToFilter: hashesByTargetToBeCached.map { $0.0.target })

        let (projectPath, updatedGraph) = try updatedGenerator.generateWithGraph(path: path, projectOnly: false)

        logger.notice("Building cacheable targets")

        try archive(updatedGraph, projectPath: projectPath, cacheProfile: cacheProfile, hashesByTargetToBeCached)

        logger.notice("All cacheable targets have been cached successfully as \(artifactBuilder.cacheOutputType.description)s", metadata: .success)
    }

    private func archive(
        _ graph: Graph,
        projectPath: AbsolutePath,
        cacheProfile: TuistGraph.Cache.Profile,
        _ hashesByCacheableTarget: [(GraphTarget, String)]
    ) throws {
        let frameworksSchemes = graph.workspace.schemes
            .filter { $0.name.contains("ProjectCache-Frameworks") }
            .filter { !($0.buildAction?.targets ?? []).isEmpty }
        let bundlesSchemes = graph.workspace.schemes
            .filter { $0.name.contains("ProjectCache-Bundles") }
            .filter { !($0.buildAction?.targets ?? []).isEmpty }

        try FileHandler.shared.inTemporaryDirectory { outputDirectory in
            for scheme in frameworksSchemes {
                let outputDirectory = outputDirectory.appending(component: scheme.name)
                try FileHandler.shared.createFolder(outputDirectory)
                try artifactBuilder.build(
                    scheme: scheme,
                    projectTarget: XcodeBuildTarget(with: projectPath),
                    configuration: cacheProfile.configuration,
                    into: outputDirectory
                )
            }

            for scheme in bundlesSchemes {
                let outputDirectory = outputDirectory.appending(component: scheme.name)
                try FileHandler.shared.createFolder(outputDirectory)
                try bundleArtifactBuilder.build(
                    scheme: scheme,
                    projectTarget: XcodeBuildTarget(with: projectPath),
                    configuration: cacheProfile.configuration,
                    into: outputDirectory
                )
            }

            let count = hashesByCacheableTarget.count
            for (index, (target, hash)) in hashesByCacheableTarget.enumerated() {
                logger.notice("Storing cacheable targets: \(target.target.name), \(index + 1) out of \(count)")

                let isFramework = target.target.product.isFramework
                let suffix = "ProjectCache-\(isFramework ? "Frameworks" : "Bundles")-\(target.target.platform.caseValue)"

                let productNameWithExtension = target.target.productName
                _ = try cache.store(
                    hash: hash,
                    paths: FileHandler.shared.glob(outputDirectory.appending(component: suffix), glob: "\(productNameWithExtension).*")
                ).toBlocking().last()
            }
        }
    }

    private func makeHashesByTargetToBeCached(
        for graph: Graph,
        cacheProfile: TuistGraph.Cache.Profile,
        targetsToFilter: [String]
    ) throws -> [(GraphTarget, String)] {
        let hashesByCacheableTarget = try cacheGraphContentHasher.contentHashes(
            for: graph,
            cacheProfile: cacheProfile,
            cacheOutputType: artifactBuilder.cacheOutputType
        )

        let graphTraveser = GraphTraverser(graph: graph)
        let filteredTargets: [GraphTarget] = {
            if targetsToFilter.isEmpty {
                return Array(hashesByCacheableTarget.keys)
            } else {
                return hashesByCacheableTarget.keys
                    .filter { targetsToFilter.contains($0.target.name) }
            }
        }()

        return try topologicalSort(
            filteredTargets,
            successors: {
                Array(graphTraveser.directTargetDependencies(path: $0.path, name: $0.target.name))
            }
        )
        .filter { target in
            guard let hash = hashesByCacheableTarget[target] else { return false }
            let cacheExists = try cache.exists(hash: hash).toBlocking().first() ?? false
            return !cacheExists
        }
        .reversed()
        .map { ($0, hashesByCacheableTarget[$0]!) }
    }
}
