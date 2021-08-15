import Foundation
import TuistCore
import TuistGraph

class CacheWorkspaceMapperProvider: WorkspaceMapperProviding {
    private let workspaceMapperProvider: WorkspaceMapperProviding
    private let targetsToFilter: [Target]

    init(workspaceMapperProvider: WorkspaceMapperProviding,
         targetsToFilter: [Target])
    {
        self.workspaceMapperProvider = workspaceMapperProvider
        self.targetsToFilter = targetsToFilter
    }

    func mapper(config: Config) -> WorkspaceMapping {
        SequentialWorkspaceMapper(
            mappers: [
                workspaceMapperProvider.mapper(config: config),
                CacheWorkspaceMapper(targetsToFilter: targetsToFilter),
            ]
        )
    }
}
