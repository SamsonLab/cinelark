import Foundation
import Observation
import CineLarkDomain

@Observable
@MainActor
final class FavoritesModel {
    private(set) var movies: [MediaSummary] = []
    private(set) var series: [MediaSummary] = []
    private(set) var people: [PersonDetail] = []
    private(set) var movieCount = 0
    private(set) var seriesCount = 0
    private(set) var peopleCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let provider: any MediaLibraryProvider

    init(provider: any MediaLibraryProvider) {
        self.provider = provider
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        async let moviesRequest = provider.favoriteMedia(
            kind: .movie,
            page: PageRequest(number: 1, size: 60)
        )
        async let seriesRequest = provider.favoriteMedia(
            kind: .series,
            page: PageRequest(number: 1, size: 60)
        )
        async let peopleRequest = provider.favoritePeople(
            page: PageRequest(number: 1, size: 60)
        )

        do {
            let page = try await moviesRequest
            guard !Task.isCancelled else { return }
            movies = page.items
            movieCount = page.total
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }

        do {
            let page = try await seriesRequest
            guard !Task.isCancelled else { return }
            series = page.items
            seriesCount = page.total
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }

        do {
            let page = try await peopleRequest
            guard !Task.isCancelled else { return }
            people = page.items
            peopleCount = page.total
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }

    }

    func dismissError() {
        errorMessage = nil
    }

    private func present(_ error: Error) {
        guard errorMessage == nil else { return }
        if let error = error as? LocalizedError,
           let description = error.errorDescription {
            errorMessage = description
        } else {
            errorMessage = "CineLark could not load favorites."
        }
    }
}
