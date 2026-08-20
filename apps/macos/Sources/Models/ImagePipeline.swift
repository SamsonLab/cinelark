import Kingfisher

@MainActor
enum CineLarkImagePipeline {
    static let cache: ImageCache = {
        let cache = ImageCache(name: "cinelark-artwork")
        cache.memoryStorage.config.totalCostLimit = 128 * 1_024 * 1_024
        cache.memoryStorage.config.expiration = .seconds(10 * 60)
        cache.diskStorage.config.sizeLimit = 512 * 1_024 * 1_024
        cache.diskStorage.config.expiration = .days(30)
        return cache
    }()
}
