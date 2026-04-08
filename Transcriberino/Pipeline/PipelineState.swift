import Foundation

enum PipelineState: Equatable {
    case idle
    case recording
    case processing
    case injecting
    case ready
}
