// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyDay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MyDay", targets: ["MyDay"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MyDay",
            dependencies: [],
            path: "Sources/MyDay"
        ),
        .testTarget(
            name: "MyDayTests",
            dependencies: ["MyDay"],
            path: "Tests/MyDayTests",
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-load-resolved-plugin",
                    "-Xfrontend", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib##TestingMacros"
                ])
            ]
        ),
    ]
)
