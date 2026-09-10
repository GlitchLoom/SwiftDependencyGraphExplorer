import ArgumentParser

@main
struct SDGE: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sdge",
        abstract: "Analyze Swift type dependencies from the command line, without opening the app.",
        subcommands: [Analyze.self, ListTypes.self],
        defaultSubcommand: Analyze.self
    )
}
