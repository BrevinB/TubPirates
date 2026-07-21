/// The selectable captain portraits — free starters plus rare treasures
/// purchasable with doubloons.
struct Avatar: Identifiable, Equatable {
    let id: String       // asset name
    let name: String
    /// Doubloon price; 0 = free (always owned) unless `earnedBy` is set.
    var price: Int = 0
    /// Trophy cosmetics: how to earn it. Set = can never be bought.
    var earnedBy: String? = nil

    static let all: [Avatar] = [
        Avatar(id: "portrait_player", name: "Sailor Pup"),
        Avatar(id: "avatar_cat", name: "First Mate Whiskers"),
        Avatar(id: "avatar_bunny", name: "Bubbles the Bunny"),
        Avatar(id: "avatar_frog", name: "Snorkel Hopper"),
        Avatar(id: "avatar_duck_yellow", name: "Classic Quack"),
        Avatar(id: "avatar_duck_pink", name: "Duchess Quackington"),
        Avatar(id: "avatar_duck_ninja", name: "Shadow Quack"),
        Avatar(id: "avatar_crab", name: "Pinchy", price: 300),
        Avatar(id: "avatar_octopus", name: "Sudsy the Octopus", price: 400),
        Avatar(id: "avatar_turtle", name: "Sir Barnacle", price: 500),
        Avatar(id: "avatar_puffer", name: "Puffbeard", price: 600),
        Avatar(id: "avatar_kraken", name: "The Kraken", price: 750),
        Avatar(id: "avatar_shark", name: "Scrubs the Shark", price: 850),
        Avatar(id: "avatar_narwhal", name: "Lord Pointington", price: 1000),
        Avatar(id: "avatar_duck_robo", name: "Quackbot 3000", price: 1250),
        Avatar(id: "avatar_duck_gold", name: "The Golden Quack", price: 2000),
        Avatar(id: "avatar_duck_diamond", name: "The Diamond Quack", price: 4000),
        Avatar(id: "avatar_duck_king", name: "The Tub King", earnedBy: "Win 25 battles"),
    ]

    static let defaultID = "portrait_player"

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? "Captain"
    }
}
