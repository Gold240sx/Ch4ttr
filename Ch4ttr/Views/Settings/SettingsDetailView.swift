import AppKit
import SwiftUI

struct SettingsDetailView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ScrollView(.vertical) {
            Group {
                switch model.selectedSection {
                case .general:
                    GeneralSectionView()
                case .engine:
                    EngineSectionView()
                case .recording:
                    RecordingSectionView()
                case .permissions:
                    PermissionsSectionView()
                case .dictionary:
                    DictionarySectionView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.windowBackground)
    }
}
