import Foundation

public struct PageWearProfile: Equatable, Sendable {
  public let stage: Int
  public let paperToneAlpha: Double
  public let edgeDullnessAlpha: Double
  public let edgeDepthFraction: Double
  public let textureAlpha: Double
  public let shadowOpacity: Double

  public init(visitCount: Int) {
    let visits = max(visitCount, 0)

    switch visits {
    case ..<2:
      stage = 0
      paperToneAlpha = 0
      edgeDullnessAlpha = 0
      edgeDepthFraction = 0
      textureAlpha = 0
      shadowOpacity = 0
    case 2..<4:
      stage = 1
      paperToneAlpha = 0.040
      edgeDullnessAlpha = 0.060
      edgeDepthFraction = 0.030
      textureAlpha = 0.018
      shadowOpacity = 0.05
    case 4..<8:
      stage = 2
      paperToneAlpha = 0.075
      edgeDullnessAlpha = 0.110
      edgeDepthFraction = 0.045
      textureAlpha = 0.032
      shadowOpacity = 0.08
    default:
      stage = 3
      paperToneAlpha = 0.120
      edgeDullnessAlpha = 0.180
      edgeDepthFraction = 0.060
      textureAlpha = 0.050
      shadowOpacity = 0.11
    }
  }
}
