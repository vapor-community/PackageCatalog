import Routing
import Vapor

public func routes(_ router: Router)throws {
    try router.register(collection: PackageController())
}
