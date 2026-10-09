import Foundation

/// One `timber list --json` row. Identity and location are required.
/// Optional Status/Todo fields default for compatibility across CLI versions.
public struct TimberListDetail: Decodable {
    public var name = ""
    public var repo = ""
    public var path: String
    public var ahead = 0
    public var behind = 0
    public var merged = false
    public var statusError = false
    public var todoDone = 0
    public var todoTotal = 0

    enum CodingKeys: String, CodingKey {
        case name, repo, path, ahead, behind, merged, statusError, todoDone, todoTotal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        repo = try container.decode(String.self, forKey: .repo)
        path = try container.decode(String.self, forKey: .path)
        ahead = (try? container.decode(Int.self, forKey: .ahead)) ?? 0
        behind = (try? container.decode(Int.self, forKey: .behind)) ?? 0
        merged = (try? container.decode(Bool.self, forKey: .merged)) ?? false
        statusError = (try? container.decode(Bool.self, forKey: .statusError)) ?? false
        todoDone = (try? container.decode(Int.self, forKey: .todoDone)) ?? 0
        todoTotal = (try? container.decode(Int.self, forKey: .todoTotal)) ?? 0
    }
}
