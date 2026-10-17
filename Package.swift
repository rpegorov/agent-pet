// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agent-pet",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "agent-pet-emit", targets: ["agent-pet-emit"]),
        .executable(name: "AgentPet", targets: ["AgentPet"]),
    ],
    targets: [
        .target(name: "PetCore", path: "Sources/PetCore"),
        .executableTarget(
            name: "agent-pet-emit",
            dependencies: ["PetCore"],
            path: "Sources/agent-pet-emit"
        ),
        .executableTarget(
            name: "AgentPet",
            dependencies: ["PetCore"],
            path: "Sources/AgentPet",
            resources: [.copy("Resources/catgirl-spritesheet.png")]
        ),
        .testTarget(
            name: "AgentPetTests",
            dependencies: ["AgentPet", "PetCore"],
            path: "Tests/AgentPetTests"
        ),
        .testTarget(
            name: "PetCoreTests",
            dependencies: ["PetCore", "agent-pet-emit"],
            path: "Tests/PetCoreTests"
        ),
    ]
)
