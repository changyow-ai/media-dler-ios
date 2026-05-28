import SwiftUI
import MediaDlerCore

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var urlText = ""
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                inputBar
                if model.tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("media-dler")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: model.settings)
            }
            .sheet(item: $model.pendingPick) { item in
                PickerView(item: item, audioFormat: model.settings.settings.audioFormat) { selection in
                    model.submit(item: item, selection: selection)
                    model.pendingPick = nil
                }
            }
            .overlay { if model.isExtracting { extractingOverlay } }
            .alert("提示", isPresented: bannerBinding) {
                Button("好", role: .cancel) { model.banner = nil }
            } message: {
                Text(model.banner ?? "")
            }
        }
    }

    private var inputBar: some View {
        HStack {
            TextField("貼上影片連結…", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(go)
            if !urlText.isEmpty {
                Button { urlText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.secondary)
            }
            Button("貼上") {
                urlText = UIPasteboard.general.string ?? ""
                go()
            }
            .buttonStyle(.bordered)
            Button("下載", action: go)
                .buttonStyle(.borderedProminent)
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private func go() {
        let text = urlText
        urlText = ""
        model.handle(text: text)
    }

    private var taskList: some View {
        List {
            ForEach(model.tasks, id: \.id) { task in
                TaskRow(task: task)
                    .swipeActions {
                        Button("刪除", role: .destructive) { model.remove(task) }
                        if task.status == .failed {
                            Button("重試") { model.retry(task) }.tint(.blue)
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.down.circle").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("從其他 App 分享連結，或在上方貼上網址即可下載。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var extractingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            ProgressView("解析中…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var bannerBinding: Binding<Bool> {
        Binding(get: { model.banner != nil }, set: { if !$0 { model.banner = nil } })
    }
}

struct TaskRow: View {
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title).font(.body).lineLimit(2)
            HStack(spacing: 6) {
                statusIcon
                Text(statusText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(task.formatLabel).font(.caption2).foregroundStyle(.secondary)
            }
            if task.status == .downloading {
                ProgressView(value: max(0, min(1, task.progress)))
            }
            if let info = task.outputUri, task.status == .completed {
                Text(info).font(.caption2).foregroundStyle(.secondary)
            }
            if let err = task.errorMessage, task.status == .failed {
                Text(err).font(.caption2).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        Image(systemName: iconName).foregroundStyle(iconColor)
    }

    private var iconName: String {
        switch task.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .downloading, .processing: return "arrow.down.circle"
        default: return "clock"
        }
    }

    private var iconColor: Color {
        switch task.status {
        case .completed: return .green
        case .failed: return .red
        case .downloading, .processing: return .blue
        default: return .secondary
        }
    }

    private var statusText: String {
        switch task.status {
        case .queued: return "等待中"
        case .extracting: return "解析中"
        case .downloading: return "下載中 \(Int(task.progress * 100))%"
        case .processing: return "處理中"
        case .completed: return "完成"
        case .failed: return "失敗"
        case .canceled: return "已取消"
        }
    }
}
