import Foundation

@main
enum Entry {
    static func main() {
        if let code = CommandLineModes.run(CommandLine.arguments) {
            exit(code)
        }
        RecapApp.main()
    }
}
