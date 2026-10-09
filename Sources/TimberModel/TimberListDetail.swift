import Foundation

/// One `timber list --json` row: the Status/Todo columns for a worktree.
/// File scope (not nested in TimberCommand) for the nesting lint.
/// Decodes defensively (missing keys default) so a newer or older timber
/// still enriches rows instead of failing the parse.
public struct TimberListDetail: Decodable {
    public var name = ""
    public var repo = ""
    public var ahead = 0
    public var behind = 0
    public var merged = false
    public var statusError = false
    public var todoDone = 0
    public var todoTotal = 0

    enum CodingKeys: String, CodingKey {
        case name, repo, ahead, behind, merged, statusError, todoDone, todoTotal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        repo = (try? container.decode(String.self, forKey: .repo)) ?? ""
        ahead = (try? container.decode(Int.self, forKey: .ahead)) ?? 0
        behind = (try? container.decode(Int.self, forKey: .behind)) ?? 0
        merged = (try? container.decode(Bool.self, forKey: .merged)) ?? false
        statusError = (try? container.decode(Bool.self, forKey: .statusError)) ?? false
        todoDone = (try? container.decode(Int.self, forKey: .todoDone)) ?? 0
        todoTotal = (try? container.decode(Int.self, forKey: .todoTotal)) ?? 0
    }
}
