// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WillDemo",
    platforms: [
        .macOS("14.0")
    ],
    dependencies: [
        // MARK: External Deps

        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.3.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.12.0"),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.4.0"
        ),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(
            url: "git@gitlab.com:PassiveLogic/platform/quantum/QuantumInterface.git",
            "0.4.0"..<"0.5.0"
        ),
        .package(
            url: "git@gitlab.com:PassiveLogic/platform/qsc-introspectionkit-driver.git",
            "0.7.1"..<"1.0.0"
        ),
        // MARK: Internal Deps

        .package(url: "git@gitlab.com:PassiveLogic/physics/QortexREPL.git", from: "0.6.3"),
    ],
    targets: [
        .executableTarget(
            name: "WillDemo",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "DockerREPLClient", package: "QortexREPL"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "QortexREPL", package: "QortexREPL"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "QSCIntrospectionKitDriver", package: "qsc-introspectionkit-driver"),
                .product(name: "QuantumInterface", package: "QuantumInterface"),
            ]
        )
    ]
)
