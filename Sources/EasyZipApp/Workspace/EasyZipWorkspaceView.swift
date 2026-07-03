import SwiftUI

struct EasyZipWorkspaceView: View {
    @StateObject private var model: EasyZipAppModel

    init(model: EasyZipAppModel = EasyZipAppModel()) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(model: model)

            if let pendingSelection = model.pendingExternalSelection {
                PendingExternalSelectionBanner(model: model, selection: pendingSelection)
            }

            Divider()

            HStack(spacing: 0) {
                FileQueueView(model: model)
                    .frame(width: 300)

                Divider()

                WorkspaceMainView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            ProgressDrawerView(model: model)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("确定"))
            )
        }
        .sheet(item: $model.passwordPrompt) { prompt in
            ArchivePasswordPromptView(
                prompt: prompt,
                submit: model.submitExtractionPassword,
                cancel: model.cancelExtractionPasswordPrompt
            )
        }
        .sheet(item: $model.conflictPrompt) { prompt in
            ArchiveConflictPromptView(
                prompt: prompt,
                resolve: model.resolveArchiveConflict
            )
            .interactiveDismissDisabled(true)
        }
    }
}
