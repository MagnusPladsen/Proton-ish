import Foundation
import Testing

@testable import NotProtonApp

@Suite("Project links")
struct ProjectLinksTests {
    @Test("The Status screen links point at the upstream projects and CrossOver's page")
    func linksPointAtTheRightPlaces() {
        #expect(ProjectLinks.notProton.absoluteString == "https://github.com/NotProtonNot/NotProton")
        #expect(ProjectLinks.highball.absoluteString == "https://github.com/gauthierpiarrette/highball")
        #expect(ProjectLinks.crossOver.absoluteString == "https://www.codeweavers.com/crossover")
    }

    @Test("Every link is https")
    func linksAreSecure() {
        for link in [ProjectLinks.notProton, ProjectLinks.highball, ProjectLinks.crossOver] {
            #expect(link.scheme == "https", "\(link)")
        }
    }
}
