//
//  HistoryView.swift
//  WalkIn
//
//  Created by Apple on 05/02/26.
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var nav: NavigationManager
    
    var body: some View {
        List(nav.path) { node in
            HStack {
                VStack(alignment: .leading) {
                    Text("Steps: \(node.stepCount)")
                        .font(.headline)
                    Text("Heading: \(Int(node.heading))°")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(node.timestamp, style: .time)
                    .font(.caption)
            }
        }
        .navigationTitle("Path History")
        .overlay {
            if nav.path.isEmpty {
                // ALTERNATIVE METHOD: Custom VStack instead of ContentUnavailableView
                VStack(spacing: 20) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 60)) // Make icon big
                        .foregroundColor(.secondary)
                    
                    Text("No Paths Yet")
                        .font(.title2)
                        .bold()
                    
                    Text("Record a path to see it here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding() // Add breathing room
            }
        }
    }
}
