import SwiftUI
import UIKit

enum AvatarImage {
    /// 고른 사진을 정사각형(얼굴이 있는 위쪽을 조금 더 살림) 400px JPEG로 줄인다
    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let target: CGFloat = 400
        let scale = target / min(image.size.width, image.size.height)
        let w = image.size.width * scale
        let h = image.size.height * scale
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let output = renderer.image { _ in
            image.draw(in: CGRect(x: (target - w) / 2, y: (target - h) * 0.3, width: w, height: h))
        }
        return output.jpegData(compressionQuality: 0.85)
    }
}

struct AvatarView: View {
    /// 사진이 바뀔 때마다 다시 그리도록
    let version: Int
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: Store.avatarURL.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .id(version)
    }
}

/// 설정 화면에서 보여주는 잠금화면 알림 모양 미리보기
struct NotificationPreview: View {
    let title: String
    let message: String
    let showsPhoto: Bool
    let version: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "app.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("지금").font(.caption).foregroundStyle(.secondary)
                }
                Text(message).font(.subheadline).lineLimit(3)
            }
            if showsPhoto {
                AvatarView(version: version, size: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
    }
}
