import Domain
import SwiftUI

/// What the Docker integration found, and what it refuses to promise.
struct DockerDetailsView: View {
    let summaries: [ScanModel.CategorySummary]
    let estimatedBytes: UInt64
    let unknownCount: Int

    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Docker resources", systemImage: "shippingbox.fill")
                    .font(.title3.weight(.semibold))

                Text(
                    LocalizedFormatters.text(
                        "About %@", locale: locale,
                        LocalizedFormatters.bytes(estimatedBytes, locale: locale))
                )
                .font(.title2)
                .monospacedDigit()

                Text(
                    """
                    An estimate, and kept separate from filesystem totals on purpose. Image \
                    layers are shared between images, so removing two images does not free the \
                    sum of their sizes.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if unknownCount > 0 {
                    CountText(
                        """
                        %lld resource reported no size. MacDevClean does not mount volumes \
                        to work one out.
                        """,
                        unknownCount
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Label(
                    "Docker removals cannot be undone. There is no Trash for them.",
                    systemImage: "exclamationmark.octagon"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
