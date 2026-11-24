// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "embedding-atlas-mcp",
    platforms: [.macOS("26.0")],
    targets: [
        // All logic lives here so the tests can import it. The executable target below
        // is only a launcher: an executable target cannot be imported by a test target.
        .target(name: "EmbeddingAtlasMCPCore"),
        .executableTarget(
            name: "embedding-atlas-mcp",
            dependencies: ["EmbeddingAtlasMCPCore"],
            // The embedded Info.plist gives the binary its bundle identifier and version,
            // which the code signature's designated requirement quotes. This server reads
            // no TCC-protected location, so the plist declares no usage descriptions.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "EmbeddingAtlasMCPCoreTests", dependencies: ["EmbeddingAtlasMCPCore"]),
    ]
)
