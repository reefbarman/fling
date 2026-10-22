// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Fling",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Fling",
            targets: ["Fling"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Fling",
            path: "Fling",
            exclude: [
                "Infrastructure/System/DefaultBrowserRegistrationNotes.md"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
