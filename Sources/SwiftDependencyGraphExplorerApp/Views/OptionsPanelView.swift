import SDGECore
import SwiftUI

struct OptionsPanelView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Analysis")
                .font(.headline)
                .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rootTypeSection
                    Divider()
                    directionSection
                    Divider()
                    depthSection
                    Divider()
                    typeFiltersSection
                    Divider()
                    referenceFiltersSection
                }
                .padding(12)
            }

            Divider()
            analyzeButton
                .padding(12)
        }
    }

    @ViewBuilder
    private var rootTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Root Type")
                .font(.subheadline.weight(.semibold))

            if let file = model.selectedFile {
                Text(file.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                if model.parsedTypes.isEmpty {
                    Label("No types found in this file", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Type", selection: selectedTypeID) {
                        Text("Select a type").tag(Optional<SwiftType.ID>.none)
                        ForEach(model.parsedTypes) { type in
                            Text("\(type.name) (\(type.kind.rawValue))")
                                .tag(Optional(type.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text("Select a Swift file from the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var depthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Depth")
                .font(.subheadline.weight(.semibold))
            Picker("Dependency depth", selection: $model.options.depth) {
                ForEach(1...3, id: \.self) { depth in
                    Text("\(depth)").tag(depth)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Direction")
                .font(.subheadline.weight(.semibold))
            Picker("Dependency direction", selection: $model.options.direction) {
                ForEach(AnalysisDirection.allCases, id: \.self) { direction in
                    Text(direction.label).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var typeFiltersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Included Types")
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                GridRow {
                    Toggle("Classes", isOn: $model.options.includeClasses)
                    Toggle("Structs", isOn: $model.options.includeStructs)
                }
                GridRow {
                    Toggle("Enums", isOn: $model.options.includeEnums)
                    Toggle("Protocols", isOn: $model.options.includeProtocols)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private var referenceFiltersSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("References")
                .font(.subheadline.weight(.semibold))
            Toggle("System types", isOn: $model.options.includeSystemTypes)
            Toggle("Third-party types", isOn: $model.options.includeThirdPartyTypes)
            Toggle("Function body references", isOn: $model.options.includeBodyReferences)

            Text("Excluded prefixes")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("UI, NS, Test", text: excludedPrefixes)
                .textFieldStyle(.roundedBorder)
        }
        .toggleStyle(.checkbox)
    }

    private var analyzeButton: some View {
        Button {
            Task { await model.analyze() }
        } label: {
            HStack(spacing: 7) {
                if model.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                Text(model.isAnalyzing ? "Analyzing..." : "Analyze")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canAnalyze)
        .keyboardShortcut(.return, modifiers: [.command])
    }

    private var selectedTypeID: Binding<SwiftType.ID?> {
        Binding(
            get: { model.selectedType?.id },
            set: model.selectType(id:)
        )
    }

    private var excludedPrefixes: Binding<String> {
        Binding(
            get: { model.options.excludedPrefixes.joined(separator: ", ") },
            set: { value in
                model.options.excludedPrefixes = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}
