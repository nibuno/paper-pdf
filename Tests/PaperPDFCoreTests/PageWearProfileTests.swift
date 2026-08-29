import Testing

@testable import PaperPDFCore

@Test("Paper character appears only after a page is revisited")
func pageWearStartsOnRevisit() {
  let untouched = PageWearProfile(visitCount: -1)
  #expect(untouched.stage == 0)
  #expect(untouched.paperToneAlpha == 0)
  #expect(untouched.edgeDullnessAlpha == 0)
  #expect(untouched.textureAlpha == 0)
  #expect(PageWearProfile(visitCount: 0).stage == 0)
  #expect(PageWearProfile(visitCount: 1).stage == 0)
  #expect(PageWearProfile(visitCount: 2).stage == 1)
}

@Test("Paper character accumulates in three bounded stages")
func pageWearStagesAreBounded() {
  #expect(PageWearProfile(visitCount: 3).stage == 1)
  #expect(PageWearProfile(visitCount: 4).stage == 2)
  #expect(PageWearProfile(visitCount: 7).stage == 2)
  #expect(PageWearProfile(visitCount: 8).stage == 3)
  #expect(PageWearProfile(visitCount: 10_000).stage == 3)
}

@Test("All paper characteristics increase together without becoming a stain")
func pageWearCharacteristicsAreMonotonicAndBounded() {
  let profiles = [2, 4, 8, 10_000].map(PageWearProfile.init(visitCount:))
  let paperTone = profiles.map(\.paperToneAlpha)
  let edgeDullness = profiles.map(\.edgeDullnessAlpha)
  let edgeDepth = profiles.map(\.edgeDepthFraction)
  let texture = profiles.map(\.textureAlpha)
  let shadow = profiles.map(\.shadowOpacity)

  #expect(paperTone == paperTone.sorted())
  #expect(edgeDullness == edgeDullness.sorted())
  #expect(edgeDepth == edgeDepth.sorted())
  #expect(texture == texture.sorted())
  #expect(shadow == shadow.sorted())
  #expect(profiles.allSatisfy { $0.paperToneAlpha <= 0.12 })
  #expect(profiles.allSatisfy { $0.edgeDullnessAlpha <= 0.18 })
  #expect(profiles.allSatisfy { $0.textureAlpha <= 0.05 })
  #expect(profiles.allSatisfy { $0.shadowOpacity <= 0.11 })

  let familiarPage = PageWearProfile(visitCount: 8)
  #expect(familiarPage.paperToneAlpha >= 0.1)
  #expect(familiarPage.edgeDullnessAlpha >= 0.15)
}
