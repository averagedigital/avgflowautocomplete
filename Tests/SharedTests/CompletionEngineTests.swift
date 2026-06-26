import XCTest
@testable import avgFlow

final class CompletionEngineTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Hybrid Service

    func testHybridReturnsDictionarySuggestionsWithoutOtherEngines() async throws {
        let dictionary = MockUserDictionary(suggestions: [
            Completion(text: "from dictionary 1", confidence: 0.91, source: .userDictionary),
            Completion(text: "from dictionary 2", confidence: 0.89, source: .userDictionary)
        ])

        let service = HybridCompletionService(
            localEngine: nil,
            cloudEngine: nil,
            userDictionary: dictionary,
            configuration: .init(
                mode: .hybrid,
                cloudAllowed: true,
                debounceMilliseconds: 0,
                cloudReplacementLengthDelta: 6
            )
        )

        let context = TextContext(textBefore: "Hello", textAfter: "", language: "en")
        let result = try await service.complete(context: context, maxTokens: 16, count: 2)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "from dictionary 1")
        XCTAssertEqual(result[0].source, .userDictionary)
    }

    func testHybridThrowsWhenNoEngineAvailableAndDictionaryIsInsufficient() async throws {
        let dictionary = MockUserDictionary(suggestions: [
            Completion(text: "single", confidence: 0.8, source: .userDictionary)
        ])

        let service = HybridCompletionService(
            localEngine: nil,
            cloudEngine: nil,
            userDictionary: dictionary,
            configuration: .init(
                mode: .hybrid,
                cloudAllowed: true,
                debounceMilliseconds: 0,
                cloudReplacementLengthDelta: 6
            )
        )

        let context = TextContext(textBefore: "Hello", textAfter: "", language: "en")

        do {
            _ = try await service.complete(context: context, maxTokens: 16, count: 2)
            XCTFail("Expected noAvailableEngine error")
        } catch let error as CompletionEngineError {
            XCTAssertEqual(error, .noAvailableEngine)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Local / Cloud Validation

    func testLocalModelManagerThrowsModelNotLoaded() async throws {
        let manager = LocalModelManager()
        let context = TextContext(textBefore: "Hello", textAfter: "", language: "en")

        do {
            _ = try await manager.complete(context: context, maxTokens: 8, count: 1)
            XCTFail("Expected runtimeUnavailable or modelNotLoaded error")
        } catch let error as LocalModelError {
            switch error {
            case .runtimeUnavailable:
                XCTAssertTrue(true)
            case .modelNotLoaded:
                XCTAssertTrue(true)
            default:
                XCTFail("Unexpected LocalModelError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloudAPIManagerValidatesConfigurationBeforeNetworking() async throws {
        let context = TextContext(textBefore: "Hello", textAfter: "", language: "en")

        let networkDisabled = CloudAPIManager(
            configuration: .init(
                provider: .openAI,
                modelIdentifier: "gpt-4o-mini",
                apiKey: "key",
                networkEnabled: false,
                timeout: 5
            )
        )

        do {
            _ = try await networkDisabled.complete(context: context, maxTokens: 8, count: 1)
            XCTFail("Expected networkDisabled error")
        } catch let error as CloudAPIError {
            switch error {
            case .networkDisabled:
                XCTAssertTrue(true)
            default:
                XCTFail("Unexpected CloudAPIError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let missingKey = CloudAPIManager(
            configuration: .init(
                provider: .openAI,
                modelIdentifier: "gpt-4o-mini",
                apiKey: nil,
                networkEnabled: true,
                timeout: 5
            )
        )

        do {
            _ = try await missingKey.complete(context: context, maxTokens: 8, count: 1)
            XCTFail("Expected missingAPIKey error")
        } catch let error as CloudAPIError {
            switch error {
            case .missingAPIKey:
                XCTAssertTrue(true)
            default:
                XCTFail("Unexpected CloudAPIError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloudAPIManagerParsesOpenAIStreamingResponse() async throws {
        let streamedBody = """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" world"}}]}

        data: [DONE]

        """

        let session = makeStubbedSession { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, [Data(streamedBody.utf8)])
        }

        let manager = CloudAPIManager(
            configuration: .init(
                provider: .openAI,
                modelIdentifier: "gpt-4.1-mini",
                apiKey: "test-key",
                networkEnabled: true,
                timeout: 5
            ),
            session: session
        )

        let context = TextContext(textBefore: "Hello", textAfter: "", language: "en")
        let result = try await manager.complete(context: context, maxTokens: 16, count: 1)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Hello world")
        XCTAssertEqual(result[0].source, .cloud)
    }

    func testCloudAPIManagerParsesOpenRouterStreamingResponseWithComments() async throws {
        let streamedBody = """
        : OPENROUTER PROCESSING

        data: {"choices":[{"delta":{"content":"First"}}]}

        data: {"choices":[{"delta":{"content":" suggestion"}}]}

        data: [DONE]

        """

        let session = makeStubbedSession { request in
            XCTAssertEqual(request.url?.path, "/api/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            return (response, [Data(streamedBody.utf8)])
        }

        let manager = CloudAPIManager(
            configuration: .init(
                provider: .openRouter,
                modelIdentifier: "google/gemini-2.5-flash",
                apiKey: "test-key",
                networkEnabled: true,
                timeout: 5
            ),
            session: session
        )

        let context = TextContext(textBefore: "Hello", textAfter: "", language: "en")
        let result = try await manager.complete(context: context, maxTokens: 16, count: 1)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "First suggestion")
        XCTAssertEqual(result[0].source, .cloud)
    }
}

private actor MockUserDictionary: UserDictionaryProviding {
    private let suggestions: [Completion]

    init(suggestions: [Completion]) {
        self.suggestions = suggestions
    }

    func quickSuggestions(for context: TextContext, limit: Int) async -> [Completion] {
        Array(suggestions.prefix(max(0, limit)))
    }
}

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, [Data]))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, chunks) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeStubbedSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, [Data])
) -> URLSession {
    URLProtocolStub.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
}
