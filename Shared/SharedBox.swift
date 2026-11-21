import Foundation

/// 앱과 위젯 확장이 같이 보는 폴더(App Group).
/// SideStore는 설치할 때 그룹 이름 뒤에 팀 ID를 붙이고 Info.plist의 ALTAppGroups에 실제 이름을 적어 준다.
/// 그룹을 못 쓰면 nil (그때는 라이브 액티비티 데이터에 실린 작은 썸네일을 쓴다).
enum SharedBox {
    static let baseGroup = "group.app.dayline.ios"

    private static func groups(in bundle: Bundle?) -> [String] {
        (bundle?.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? []
    }

    /// 확장이면 감싸고 있는 앱 번들(…/Dayline.app)
    private static var hostBundle: Bundle? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return nil }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    static let container: URL? = {
        var ids = groups(in: .main) + groups(in: hostBundle)
        ids.append(baseGroup)
        for id in ids {
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { continue }
            // 권한이 없는데 경로만 돌려주는 경우가 있어 실제로 쓸 수 있는지 확인
            if FileManager.default.isWritableFile(atPath: url.path) || FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }()

    static func file(_ name: String) -> URL? { container?.appendingPathComponent(name) }
}
