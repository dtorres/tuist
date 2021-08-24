import Foundation

/// Contains the description of a dependency that can be installed using Swift Package Manager.
public struct SwiftPackageManagerDependencies: Codable, Equatable {
    /// List of packages that will be installed using Swift Package Manager.
    public let packages: [Package]

    /// The custom `Product` type to be used for SPM targets.
    /// Unless provided in this map, Tuist will use the product type defined in the respective Package.swift manifest.
    /// In case no explicit product type is defined in the Package.swift, Tuist will default to a `.framework` when the target has resources and `.staticFramework` otherwise
    public let productTypes: [String: Product]

    /// Set of deployment targets to be used when the SPM package does not specify a target version.
    public let deploymentTargets: Set<DeploymentTarget>

    /// Creates `SwiftPackageManagerDependencies` instance.
    /// - Parameter packages: List of packages that will be installed using Swift Package Manager.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter deploymentTargets: Set of deployment targets to be used when the SPM package does not specify a target version.
    public init(_ packages: [Package], productTypes: [String: Product] = [:], deploymentTargets: Set<DeploymentTarget> = []) {
        self.packages = packages
        self.productTypes = productTypes
        self.deploymentTargets = deploymentTargets
    }
}

// MARK: - ExpressibleByArrayLiteral

extension SwiftPackageManagerDependencies: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Package...) {
        packages = elements
        productTypes = [:]
        deploymentTargets = []
    }
}
