import EmbeddingAtlasMCPCore

// Launcher only. Everything testable lives in EmbeddingAtlasMCPCore, which the test
// target imports; an executable target cannot be imported. This server takes no settings.
await EmbeddingAtlasMCPServer.run()
