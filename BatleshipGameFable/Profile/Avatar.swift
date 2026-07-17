/// The selectable captain portraits — a mix of pets and rubber duckies.
struct Avatar: Identifiable, Equatable {
    let id: String       // asset name
    let name: String

    static let all: [Avatar] = [
        Avatar(id: "portrait_player", name: "Sailor Pup"),
        Avatar(id: "avatar_cat", name: "First Mate Whiskers"),
        Avatar(id: "avatar_bunny", name: "Bubbles the Bunny"),
        Avatar(id: "avatar_frog", name: "Snorkel Hopper"),
        Avatar(id: "avatar_duck_yellow", name: "Classic Quack"),
        Avatar(id: "avatar_duck_pink", name: "Duchess Quackington"),
        Avatar(id: "avatar_duck_ninja", name: "Shadow Quack"),
    ]

    static let defaultID = "portrait_player"

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? "Captain"
    }
}
