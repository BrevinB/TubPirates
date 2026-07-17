/// The selectable captain portraits — free starters plus rare treasures
/// purchasable with doubloons.
struct Avatar: Identifiable, Equatable {
    let id: String       // asset name
    let name: String
    /// Doubloon price; 0 = free (always owned).
    var price: Int = 0

    static let all: [Avatar] = [
        Avatar(id: "portrait_player", name: "Sailor Pup"),
        Avatar(id: "avatar_cat", name: "First Mate Whiskers"),
        Avatar(id: "avatar_bunny", name: "Bubbles the Bunny"),
        Avatar(id: "avatar_frog", name: "Snorkel Hopper"),
        Avatar(id: "avatar_duck_yellow", name: "Classic Quack"),
        Avatar(id: "avatar_duck_pink", name: "Duchess Quackington"),
        Avatar(id: "avatar_duck_ninja", name: "Shadow Quack"),
        Avatar(id: "avatar_octopus", name: "Sudsy the Octopus", price: 400),
        Avatar(id: "avatar_turtle", name: "Sir Barnacle", price: 500),
        Avatar(id: "avatar_kraken", name: "The Kraken", price: 750),
        Avatar(id: "avatar_duck_gold", name: "The Golden Quack", price: 1500),
    ]

    static let defaultID = "portrait_player"

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? "Captain"
    }
}
