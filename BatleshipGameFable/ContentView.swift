//
//  ContentView.swift
//  BatleshipGameFable
//
//  Created by Brevin Blalock on 7/15/26.
//

import SwiftUI
import BathtubEngine

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Fleet size: \(ShipKind.standardFleet.count)")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
