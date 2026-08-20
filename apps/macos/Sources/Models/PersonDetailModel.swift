import Foundation
import Observation
import CineLarkDomain

@Observable
@MainActor
final class PersonDetailModel {
    let credit: PersonCredit
    private(set) var detail: PersonDetail?
    private(set) var works: [MediaSummary] = []
    private(set) var workCount = 0
    private(set) var isLoading = false
    private(set) var isUpdatingFavorite = false
    var errorMessage: String?

    @ObservationIgnored private let provider: any MediaLibraryProvider

    init(credit: PersonCredit, provider: any MediaLibraryProvider) {
        self.credit = credit
        self.provider = provider
    }

    var name: String {
        detail?.name ?? credit.name
    }

    var avatarURL: URL? {
        detail?.avatarURL ?? credit.avatarURL
    }

    var isFavorite: Bool {
        detail?.isFavorite ?? false
    }

    func load() async {
        guard !isLoading, detail == nil else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        async let detailRequest = provider.person(id: credit.id)
        async let worksRequest = provider.works(
            forPersonID: credit.id,
            page: PageRequest(number: 1, size: 60),
            sort: .newest
        )

        do {
            let loadedDetail = try await detailRequest
            guard !Task.isCancelled else { return }
            detail = loadedDetail
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }

        do {
            let page = try await worksRequest
            guard !Task.isCancelled else { return }
            works = page.items
            workCount = page.total
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func addToFavorites() async {
        guard !isFavorite, !isUpdatingFavorite else { return }
        isUpdatingFavorite = true
        defer { isUpdatingFavorite = false }
        do {
            let result = try await provider.setFavorite(
                true,
                target: FavoriteTarget(id: credit.id, kind: .person)
            )
            guard let detail else { return }
            self.detail = PersonDetail(
                id: detail.id,
                name: detail.name,
                avatarURL: detail.avatarURL,
                isFavorite: result,
                tmdbID: detail.tmdbID,
                imdbID: detail.imdbID
            )
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
            errorMessage = "CineLark could not load this person."
        }
    }
}
