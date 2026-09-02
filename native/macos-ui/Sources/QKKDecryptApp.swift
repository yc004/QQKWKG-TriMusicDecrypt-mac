import AppKit
import FullDiskAccess
import PermissionFlow
import SwiftUI

@main
struct QKKDecryptApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("didAcknowledgeFreeNotice") private var didAcknowledgeFreeNotice = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .toggleStyle(.switch)
                .frame(
                    minWidth: 560, idealWidth: 620, maxWidth: 680,
                    minHeight: 380, idealHeight: 400, maxHeight: 400
                )
                .alert("本软件为免费软件", isPresented: Binding(
                    get: { !didAcknowledgeFreeNotice },
                    set: { if !$0 { didAcknowledgeFreeNotice = true } }
                )) {
                    Button("继续使用") { didAcknowledgeFreeNotice = true }
                } message: {
                    Text("如果你是付费获取的，请立即退款。本项目仅供学习交流使用，禁止商用和倒卖。")
                }
                .alert("操作未完成", isPresented: Binding(
                    get: { model.lastError != nil },
                    set: { if !$0 { model.lastError = nil } }
                )) {
                    Button("好", role: .cancel) { model.lastError = nil }
                } message: {
                    Text(model.lastError ?? "未知错误")
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 620, height: 400)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("打开输出目录") { model.openOutputDirectory() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("查看运行日志") { model.selection = .activity }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .toggleStyle(.switch)
                .frame(width: 560, height: 440)
        }

    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.selection ?? .workbench {
                case .workbench: WorkbenchView()
                case .activity: ActivityView()
                }
            }
            .navigationTitle((model.selection ?? .workbench).title)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    StatusIndicator(text: model.statusText, running: model.isRunning)
                    Button("打开输出目录", systemImage: "folder") { model.openOutputDirectory() }
                        .help("在访达中打开输出目录")
                    Menu("更多操作", systemImage: "ellipsis.circle") {
                        Button("QQ 音乐访问权限…", systemImage: "hand.raised") {
                            presentFullDiskAccessGuide()
                        }
                        Button("运行日志…", systemImage: "text.alignleft") {
                            model.selection = .activity
                        }
                        Divider()
                        SettingsLink {
                            Label("设置…", systemImage: "gearshape")
                        }
                    }
                }
            }
        }
    }
}

struct WorkbenchView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            WorkbenchBackdrop().ignoresSafeArea()
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("拖入音乐，批量解密")
                        .font(.title2.bold())
                    Text("一次可添加多个文件或文件夹，平台和格式会自动识别。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                AutomaticDropZone()

                if !model.automaticInputItems.isEmpty {
                    HStack(spacing: 12) {
                        Label("输出位置", systemImage: "folder")
                            .font(.headline)
                        Text(model.outputDirectory.isEmpty ? "使用默认输出目录" : model.outputDirectory)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("更改…") { model.chooseDirectory { model.outputDirectory = $0 } }
                            .modifier(AdaptiveGlassButton())
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                }

                if model.hasStartedTask {
                    HomeTaskStatusPanel()
                } else {
                    Button("开始解密", systemImage: "lock.open.fill") {
                        model.startAutomaticDecrypt()
                    }
                    .modifier(AdaptiveGlassButton(prominent: true))
                    .controlSize(.large)
                    .disabled(model.automaticInputItems.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                }

            }
            .frame(maxWidth: 500, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }
}

struct HomeTaskStatusPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusSymbol)
                    .font(.title3)
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusText)
                    .font(.headline)
                Text(model.taskStatusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if model.isRunning {
                Button("停止", systemImage: "stop.fill", role: .destructive) { model.stop() }
                    .modifier(AdaptiveGlassButton())
            } else {
                Button("再次解密", systemImage: "arrow.clockwise") { model.startAutomaticDecrypt() }
                    .modifier(AdaptiveGlassButton(prominent: true))
            }
        }
        .padding(12)
        .modifier(GlassPanel(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前解密状态：\(model.statusText)")
    }

    private var statusSymbol: String {
        if model.statusText.contains("失败") { return "xmark.circle.fill" }
        if model.statusText.contains("完成") { return "checkmark.circle.fill" }
        return "stop.circle.fill"
    }

    private var statusColor: Color {
        if model.statusText.contains("失败") { return .red }
        if model.statusText.contains("完成") { return .green }
        return .secondary
    }
}

struct AutomaticDropZone: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("didCompleteFullDiskAccessGuide") private var didCompletePermissionGuide = false
    @State private var isTargeted = false

    var body: some View {
        Group {
            if !model.automaticInputItems.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.green)
                            .symbolEffect(.bounce, value: model.automaticInputItems.count)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已添加 \(model.automaticInputItems.count) 个项目")
                                .font(.headline)
                            Text("共 \(model.detectedFileCount) 个可解密文件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.hasQQAutomaticInput {
                            Button("授权…", systemImage: "hand.raised") { presentFullDiskAccessGuide() }
                                .modifier(AdaptiveGlassButton(prominent: true))
                        }
                        Button("继续添加…", systemImage: "plus") { model.chooseAutomaticInput() }
                            .modifier(AdaptiveGlassButton())
                    }

                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(model.automaticInputItems) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: item.platform.symbol)
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 18)
                                    Text(item.displayName)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(item.platform.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(item.fileCount) 个")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Button("移除", systemImage: "xmark.circle.fill") {
                                        model.removeAutomaticInput(item)
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .disabled(model.isRunning)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .frame(maxHeight: 80)
                }
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "arrow.down.document")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.accentColor)
                    Text(isTargeted ? "松开即可批量添加" : "拖入多个文件或文件夹")
                        .font(.headline)
                    Text("QQ · 酷我 · 酷狗 · 网易云")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("选择…") { model.chooseAutomaticInput() }
                        .modifier(AdaptiveGlassButton())
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(14)
        .background(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .modifier(GlassPanel(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.28),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [8, 6])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.acceptAutomaticInputs(urls)
        } isTargeted: { isTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("音乐文件拖放区域")
        .onChange(of: model.hasQQAutomaticInput) { _, hasQQ in
            if hasQQ, !didCompletePermissionGuide {
                didCompletePermissionGuide = true
                presentFullDiskAccessGuide()
            }
        }
    }
}

struct BatchTranscodeSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var advancedOptionsExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("批量转码").font(.largeTitle.bold())
                    Text("这是次要工具；日常解密只需返回主窗口拖入文件。")
                        .foregroundStyle(.secondary)
                    TranscodeWorkflow(advancedOptionsExpanded: $advancedOptionsExpanded)
                }
                .padding(28)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isRunning {
                        Button("停止", role: .destructive) { model.stop() }
                    } else {
                        Button("开始转码", systemImage: "play.fill") { model.startTranscode() }
                            .disabled(model.transcodeInput.isEmpty)
                    }
                }
            }
        }
        .frame(width: 640, height: 480)
    }
}

@MainActor
private func presentFullDiskAccessGuide() {
    FullDiskAccessPermissionFlow.shared.present()
}

@MainActor
private final class FullDiskAccessPermissionFlow {
    static let shared = FullDiskAccessPermissionFlow()

    private let controller = PermissionFlowController(
        configuration: PermissionFlowConfiguration(localeIdentifier: "zh-Hans")
    )

    private init() {}

    func present() {
        // FullDiskAccess performs a real TCC-protected directory probe. On
        // macOS 10.15+ this registers the current signed app in the Full Disk
        // Access service before PermissionFlow presents its native drag card.
        _ = FullDiskAccess.isGranted

        let mouse = NSEvent.mouseLocation
        controller.authorize(
            pane: .fullDiskAccess,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: CGRect(x: mouse.x - 16, y: mouse.y - 16, width: 32, height: 32)
        )
    }
}

struct DecryptWorkflow: View {
    @EnvironmentObject private var model: AppModel
    @Binding var advancedOptionsExpanded: Bool

    var body: some View {
        VStack(spacing: 18) {
            StepCard(number: 1, title: "选择音乐平台", symbol: "music.note.list") {
                NativeActivityPicker(options: MusicPlatform.allCases, selection: $model.platform) { item in
                    Label(item.title, systemImage: item.symbol)
                }
            }
            StepCard(number: 2, title: "选择输入和输出", symbol: "folder") {
                VStack(spacing: 12) {
                    PathRow(
                        title: "输入", subtitle: "支持单个文件或整个目录",
                        path: Binding(
                            get: { model.inputPaths[model.platform, default: ""] },
                            set: { model.inputPaths[model.platform] = $0 }
                        ), buttonTitle: "选择…"
                    ) { model.chooseInput(for: model.platform) }
                    Divider()
                    PathRow(
                        title: "输出", subtitle: "留空时使用默认输出目录",
                        path: $model.outputDirectory, buttonTitle: "更改…"
                    ) { model.chooseDirectory { model.outputDirectory = $0 } }
                }
            }
            StepCard(number: 3, title: "确认处理方式", symbol: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("目标格式", systemImage: "waveform")
                        Spacer()
                        Picker("目标格式", selection: Binding(
                            get: { model.targetFormats[model.platform, default: "auto"] },
                            set: { model.targetFormats[model.platform] = $0 }
                        )) {
                            ForEach(model.formats, id: \.self) { Text(formatLabel($0)).tag($0) }
                        }.labelsHidden().frame(width: 170)
                    }
                    Toggle("解密后转换为目标格式", isOn: $model.transcodeEnabled)
                    DisclosureGroup("高级选项", isExpanded: $advancedOptionsExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("递归扫描子目录", isOn: $model.recursive)
                            Toggle("自动补充封面", isOn: $model.embedCover)
                            Toggle("补充专辑信息", isOn: $model.supplementAlbum)
                        }.padding(.top, 10)
                    }
                }
            }
        }
    }
}

struct TranscodeWorkflow: View {
    @EnvironmentObject private var model: AppModel
    @Binding var advancedOptionsExpanded: Bool

    var body: some View {
        VStack(spacing: 18) {
            StepCard(number: 1, title: "选择输入和输出", symbol: "folder") {
                VStack(spacing: 12) {
                    PathRow(title: "输入", subtitle: "选择包含音频文件的目录", path: $model.transcodeInput, buttonTitle: "选择…") {
                        model.chooseDirectory { model.transcodeInput = $0 }
                    }
                    Divider()
                    PathRow(title: "输出", subtitle: "转换后的文件保存在这里", path: $model.transcodeOutput, buttonTitle: "更改…") {
                        model.chooseDirectory { model.transcodeOutput = $0 }
                    }
                }
            }
            StepCard(number: 2, title: "选择输出格式", symbol: "waveform.badge.plus") {
                VStack(alignment: .leading, spacing: 14) {
                    NativeActivityPicker(
                        options: model.formats.filter { $0 != "auto" },
                        selection: $model.transcodeFormat
                    ) { Text(formatLabel($0)) }
                    DisclosureGroup("高级选项", isExpanded: $advancedOptionsExpanded) {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            GridRow {
                                Text("采样率").foregroundStyle(.secondary)
                                Picker("采样率", selection: $model.sampleRate) {
                                    Text("保持原始").tag(0)
                                    ForEach(model.sampleRates.filter { $0 > 0 }, id: \.self) { Text("\($0) Hz").tag($0) }
                                }.labelsHidden()
                            }
                            GridRow {
                                Text("比特率").foregroundStyle(.secondary)
                                Picker("比特率", selection: $model.bitrate) {
                                    Text("自动").tag(0)
                                    ForEach(model.bitrates.filter { $0 > 0 }, id: \.self) { Text("\($0) kbps").tag($0) }
                                }.labelsHidden()
                            }
                        }
                        Stepper("并发任务：\(model.workerCount)", value: $model.workerCount, in: 1...4)
                        Toggle("递归扫描子目录", isOn: $model.recursive)
                    }.padding(.top, 4)
                }
            }
        }
    }
}

struct ActionBar: View {
    @EnvironmentObject private var model: AppModel
    let readyToRun: Bool
    let missingInputMessage: String

    var body: some View {
        AdaptiveGlassContainer(spacing: 12) {
            HStack(spacing: 14) {
                if model.isRunning {
                    ProgressView().controlSize(.small)
                    StatusCopy(title: model.statusText, detail: "可以在“任务记录”中查看实时输出。")
                } else {
                    Image(systemName: readyToRun ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(readyToRun ? Color.green : Color.secondary)
                    StatusCopy(
                        title: readyToRun ? "准备就绪" : "等待选择输入",
                        detail: readyToRun ? "检查选项后即可开始，配置会自动保存。" : missingInputMessage
                    )
                }
                Spacer(minLength: 20)
                Button("任务记录", systemImage: "clock") { model.selection = .activity }
                    .modifier(AdaptiveGlassButton())
                if model.isRunning {
                    Button("停止", systemImage: "stop.fill", role: .destructive) { model.stop() }
                        .modifier(AdaptiveGlassButton())
                } else {
                    Button(model.taskKind == .decrypt ? "开始解密" : "开始转码", systemImage: "play.fill") {
                        if model.taskKind == .decrypt { model.startDecrypt() } else { model.startTranscode() }
                    }
                    .modifier(AdaptiveGlassButton(prominent: true))
                    .disabled(!readyToRun)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .modifier(GlassPanel(cornerRadius: 22))
        }
        .frame(maxWidth: 936)
    }
}

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            WorkbenchBackdrop().ignoresSafeArea()
            VStack(spacing: 16) {
                AdaptiveGlassContainer(spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: model.isRunning ? "arrow.trianglehead.2.clockwise.rotate.90" : statusSymbol)
                            .font(.title2).foregroundStyle(model.isRunning ? Color.accentColor : statusColor)
                            .symbolEffect(.pulse, isActive: model.isRunning)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.statusText).font(.title2.bold())
                            Text(model.isRunning ? "任务正在后台处理，可以返回工作台继续查看配置。" : "这里显示最近一次任务的状态和本次会话日志。")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.isRunning { ProgressView().controlSize(.small) }
                        Button("打开输出目录", systemImage: "folder") { model.openOutputDirectory() }
                            .modifier(AdaptiveGlassButton())
                        if model.isRunning {
                            Button("停止", systemImage: "stop.fill", role: .destructive) { model.stop() }
                                .modifier(AdaptiveGlassButton())
                        }
                    }
                    .padding(18)
                    .modifier(GlassPanel(cornerRadius: 22))
                }
                ScrollView {
                    Text(model.logs.isEmpty ? "任务开始后，运行信息会显示在这里。" : model.logs)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(model.logs.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(22)
                }
                .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.separator.opacity(0.45), lineWidth: 0.5)
                }
                AdaptiveGlassContainer(spacing: 10) {
                    HStack {
                        Text("日志仅保存在当前会话中").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("返回工作台", systemImage: "arrow.backward") { model.selection = .workbench }
                            .modifier(AdaptiveGlassButton())
                        Button("清空日志", systemImage: "trash") { model.logs = "" }
                            .modifier(AdaptiveGlassButton())
                            .disabled(model.logs.isEmpty)
                    }
                    .padding(12)
                    .modifier(GlassPanel(cornerRadius: 18))
                }
            }
            .padding(22)
        }
    }

    private var statusSymbol: String { model.statusText == "已完成" ? "checkmark.circle.fill" : "clock" }
    private var statusColor: Color { model.statusText == "已完成" ? .green : .secondary }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("输出") {
                Picker("目录模式", selection: $model.outputMode) {
                    Text("共享统一输出目录").tag("shared")
                    Text("每个平台单独目录").tag("per_platform")
                }
                LabeledContent("默认输出目录") {
                    PathControl(path: $model.outputDirectory, buttonTitle: "选择…") {
                        model.chooseDirectory { model.outputDirectory = $0 }
                    }
                }
                Toggle("默认递归扫描子目录", isOn: $model.recursive)
            }
            Section("媒体处理默认值") {
                Toggle("解密成功后进行转码", isOn: $model.transcodeEnabled)
                Toggle("自动补充封面", isOn: $model.embedCover)
                Toggle("补充专辑信息", isOn: $model.supplementAlbum)
            }
            Section("QQ 音乐权限") {
                LabeledContent("完全磁盘访问权限") {
                    Button("打开授权引导…", systemImage: "hand.raised") {
                        presentFullDiskAccessGuide()
                    }
                }
                Text("仅 musicex 文件需要读取 QQ 音乐客户端的登录信息；普通 QTag/V1 文件仍可离线处理。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Text("关闭设置窗口时自动保存").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("重新读取") { Task { await model.loadConfiguration() } }
                }
            }
        }
        .formStyle(.grouped).padding(18)
        .onDisappear { Task { await model.saveConfiguration() } }
    }
}

struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let symbol: String
    let content: Content

    init(number: Int, title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text(String(number)).font(.caption.bold()).frame(width: 24, height: 24)
                        .background(Color.accentColor, in: Circle()).foregroundStyle(.white)
                    Label(title, systemImage: symbol).font(.headline)
                }
                content
            }.padding(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PathRow: View {
    let title: String
    let subtitle: String
    @Binding var path: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }.frame(width: 145, alignment: .leading)
            TextField("未选择", text: $path).textFieldStyle(.roundedBorder)
            Button(buttonTitle, action: action)
                .modifier(AdaptiveGlassButton())
        }
    }
}

struct StatusCopy: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct StatusIndicator: View {
    let text: String
    let running: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(running ? Color.accentColor : Color.secondary).frame(width: 7, height: 7)
            Text(text).font(.caption.weight(.medium))
        }.padding(.horizontal, 10).padding(.vertical, 6).modifier(GlassCapsule())
    }
}

struct GlassCapsule: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) { content.glassEffect(.regular, in: .capsule) }
        else { content.background(.regularMaterial, in: Capsule()) }
    }
}

struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct AdaptiveGlassButton: ViewModifier {
    var prominent = false

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) }
            else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) }
            else { content.buttonStyle(.bordered) }
        }
    }
}

struct AdaptiveGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

struct NativeActivityPicker<Option: Hashable & Sendable, LabelContent: View>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> LabelContent

    init(
        options: [Option],
        selection: Binding<Option>,
        @ViewBuilder label: @escaping (Option) -> LabelContent
    ) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    @ViewBuilder var body: some View {
        if #available(macOS 27.0, *) {
            picker
                .pickerStyle(.tabs)
                .controlSize(.large)
        } else {
            picker
                .pickerStyle(.segmented)
                .controlSize(.large)
        }
    }

    private var picker: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { option in
                label(option).tag(option)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}

struct WorkbenchBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Color.accentColor.opacity(0.09), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
        }
    }
}

struct PathControl: View {
    @Binding var path: String
    let buttonTitle: String
    let action: () -> Void
    var body: some View {
        HStack {
            TextField("未选择", text: $path).textFieldStyle(.roundedBorder)
            Button(buttonTitle, action: action)
                .modifier(AdaptiveGlassButton())
        }.frame(minWidth: 360)
    }
}

private func formatLabel(_ value: String) -> String {
    value == "auto" ? "自动（保留原格式）" : value.uppercased()
}
