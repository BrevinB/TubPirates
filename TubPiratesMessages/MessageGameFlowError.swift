//
//  MessageGameFlowError.swift
//  TubPirates
//
//  Created by Brevin Blalock on 8/30/26.
//

import Foundation

enum MessageGameFlowError: LocalizedError, Equatable {
    case missingChallenge
    case invalidChallenge
    case notSecondPlayer
    case missingSession
    case missingBattle
    case notYourTurn
    case missingTarget
    case incompleteFleet
    case staleMessage

    var errorDescription: String? {
        switch self {
        case .missingChallenge:
            return "No challenge is currently loaded."
        case .invalidChallenge:
            return "This challenge cannot be joined"
        case .notSecondPlayer:
            return "Only the invited player can join this challenge"
        case .missingSession:
            return "This message does not contain a valid game session"
        case .missingBattle:
            return "No active battle is loaded."
        case .notYourTurn:
            return "It isn't your turn."
        case .missingTarget:
            return "Select a target before firing."
        case .incompleteFleet:
            return "Place all five ships before continuing."
        case .staleMessage:
            return "This is an older turn. Open the newest Tub Pirates message."
        }
    }
}
