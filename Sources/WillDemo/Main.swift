import ArgumentParser
import DockerREPLClient
import Foundation
import Hummingbird
import HummingbirdWebSocket
import QSCIntrospectionKitDriver
import QortexREPL
import QuantumInterface

@main
struct Main: AsyncParsableCommand {
    @Option(help: "The path to a custom seccomp profile needed to run a REPL container.")
    var seccompProfilePath: String

    @Option(help: "The path the millrock site")
    var sitePath: String

    mutating func run() async throws {
        let client = DockerREPLClient(
            config: DockerConfiguration(
                dockerExecutablePath: "/usr/local/bin/docker",
                seccompProfilePath: URL(fileURLWithPath: seccompProfilePath),
                hostVolumesDirectory: FileManager.default.temporaryDirectory,
                siteVarName: "site"  // This seems odd, but it prevents a circular reference if the LLM ever assigns a variable called
                    // "site" during an introspection that uses "site.find".
            ))
        let actor = try await SomeActor(client: client, site: try retrieveSite())
        let wsRouter = Router(context: BasicWebSocketRequestContext.self)
        let router = Router()
        router.add(
            middleware: CORSMiddleware(
                allowOrigin: .all,
                allowHeaders: [
                    .accessControlAllowOrigin, .contentType, .accept, .authorization, .origin,
                    .userAgent,
                ],
                allowMethods: [.post]
            ))
        wsRouter.ws(
            "/inference", shouldUpgrade: { _, _ in .upgrade() }, onUpgrade: actor.inference)
        let app = Hummingbird.Application(
            router: router,
            server: .http1WebSocketUpgrade(
                webSocketRouter: wsRouter,
                configuration: WebSocketServerConfiguration(
                    autoPing: .enabled(timePeriod: .seconds(120)), closeTimeout: .seconds(120))
            ),
            configuration: .init(address: .hostname("0.0.0.0", port: 8008))
        )
        try await app.run()
    }

    private func retrieveSite() throws -> Quantum.Site.CGraph {
        let data = try Data(
            contentsOf: URL(fileURLWithPath: sitePath))
        let site = try RootedQuantumGraphDecoder(options: [.ignoreState]).decode(
            withRoot: Quantum.Site.self, from: data)
        return try site.withHyperGraph()
    }
}

actor SomeActor {
    let repl: REPLInterface

    init(client: DockerREPLClient, site: Quantum.Site.CGraph) async throws {
        self.repl = try await client.startContainer(
            using: ContainerStorageKey(siteID: SiteID(), userID: UserID()))
        try await repl.silenceAssignments(timeout: .seconds(60))
        try await repl.saveAndLoadSiteGraph(site, as: "site")
        try await repl.loadComputedAttributes()
    }

    func inference(
        inbound: WebSocketInboundStream,
        outbound: WebSocketOutboundWriter,
        context _: WebSocketRouterContext<BasicWebSocketRequestContext>
    ) async {
        do {
            for try await msg in inbound.messages(maxSize: .max) {
                switch msg {
                case let .text(text):
                    print(text)
                    let res = try await repl.sendCommand(.swift(text))
                    if case let .printout(response) = res.first {
                        print(response)
                        try await outbound.write(.text(response))
                    } else {
                        try await outbound.write(.text(""))
                    }
                case .binary: fatalError("")
                }
            }
        } catch {}
    }
}
