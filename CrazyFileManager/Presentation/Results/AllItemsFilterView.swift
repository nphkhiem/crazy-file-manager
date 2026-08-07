import SwiftUI

struct AllItemsFilterView: View {
  let filters: AllItemsFilters
  let onChange: (AllItemsFilters) -> Void

  private static let kindOrder: [StorageItemKind] = [
    .file, .folder, .package, .symbolicLink, .other,
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      VStack(alignment: .leading, spacing: CFMDesign.Spacing.compact) {
        Text("Kind").font(.subheadline.weight(.semibold))
        ForEach(Self.kindOrder, id: \.self) { kind in
          Toggle(
            Self.kindLabel(for: kind),
            isOn: Binding(
              get: { filters.kinds.contains(kind) },
              set: { isOn in
                var updated = filters
                if isOn {
                  updated.kinds.insert(kind)
                } else {
                  updated.kinds.remove(kind)
                }
                onChange(updated)
              }
            )
          )
          .accessibilityIdentifier("allItemsKindFilter\(Self.kindLabel(for: kind))")
        }
      }

      Divider()

      Picker(
        "Hidden",
        selection: Binding(
          get: { filters.hidden },
          set: { onChange(Self.updated(filters, hidden: $0)) }
        )
      ) {
        Text("Any").tag(TriStateFilter.any)
        Text("Hidden only").tag(TriStateFilter.onlyTrue)
        Text("Visible only").tag(TriStateFilter.onlyFalse)
      }
      .accessibilityLabel("Hidden")
      .accessibilityIdentifier("allItemsHiddenFilter")

      Picker(
        "Cloud",
        selection: Binding(
          get: { filters.cloudOnly },
          set: { onChange(Self.updated(filters, cloudOnly: $0)) }
        )
      ) {
        Text("Any").tag(TriStateFilter.any)
        Text("Cloud-only only").tag(TriStateFilter.onlyTrue)
        Text("Local only").tag(TriStateFilter.onlyFalse)
      }
      .accessibilityLabel("Cloud")
      .accessibilityIdentifier("allItemsCloudOnlyFilter")

      Divider()

      HStack {
        Text("Minimum Disk Used")
        TextField(
          "bytes",
          value: Binding(
            get: { filters.minimumDiskUsedBytes },
            set: { onChange(Self.updated(filters, minimumDiskUsedBytes: $0)) }
          ),
          format: .number
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 100)
        .accessibilityLabel("Minimum Disk Used")
        .accessibilityIdentifier("allItemsMinimumDiskUsedField")
      }
    }
    .padding(CFMDesign.Spacing.comfortable)
    .frame(width: 240)
  }

  private static func updated(
    _ filters: AllItemsFilters,
    hidden: TriStateFilter? = nil,
    cloudOnly: TriStateFilter? = nil,
    minimumDiskUsedBytes: Int64?? = nil
  ) -> AllItemsFilters {
    var updated = filters
    if let hidden {
      updated.hidden = hidden
    }
    if let cloudOnly {
      updated.cloudOnly = cloudOnly
    }
    if let minimumDiskUsedBytes {
      updated.minimumDiskUsedBytes = minimumDiskUsedBytes
    }
    return updated
  }

  private static func kindLabel(for kind: StorageItemKind) -> String {
    switch kind {
    case .file: "Files"
    case .folder: "Folders"
    case .symbolicLink: "Symbolic Links"
    case .package: "Packages"
    case .other: "Other"
    }
  }
}
