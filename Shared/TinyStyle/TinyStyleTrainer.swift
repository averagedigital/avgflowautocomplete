import Foundation

actor TinyStyleTrainer {
    static let shared = TinyStyleTrainer()

    // MARK: - Dependencies

    private let model: TinyStyleLMModel
    private let replayBuffer: TinyStyleReplayBuffer
    private let eventLogger: TinyStyleEventLogger

    // MARK: - Runtime

    private var acceptedSinceLastStep = 0
    private var latestMetrics: TinyStyleTrainingMetrics?

    // MARK: - Init

    init(
        model: TinyStyleLMModel = TinyStyleLMModel(),
        replayBuffer: TinyStyleReplayBuffer = TinyStyleReplayBuffer(),
        eventLogger: TinyStyleEventLogger = TinyStyleEventLogger()
    ) {
        self.model = model
        self.replayBuffer = replayBuffer
        self.eventLogger = eventLogger
    }

    // MARK: - Host App API

    func restore() async {
        await model.loadIfNeeded()
        try? await replayBuffer.load()
    }

    func recordHostAccepted(context: String, completion: String, language: String) async {
        await model.loadIfNeeded()
        guard let example = TinyStyleTokenizer.makeExample(
            context: context,
            completion: completion,
            language: language
        ) else {
            return
        }

        await replayBuffer.add(example)
        acceptedSinceLastStep += 1
        _ = await maybeTrainStep()
    }

    func runTrainingCycle(force: Bool = false) async -> TinyStyleTrainingMetrics? {
        await model.loadIfNeeded()
        await importKeyboardEvents()

        if force {
            return await trainStep()
        }
        return await maybeTrainStep()
    }

    func latestTrainingMetrics() -> TinyStyleTrainingMetrics? {
        latestMetrics
    }

    func hasSufficientPersonalData(minExamples: Int = 120) async -> Bool {
        let total = await replayBuffer.count()
        return total >= minExamples
    }

    // MARK: - Keyboard API

    func logKeyboardAccepted(context: String, completion: String, language: String) async {
        let event = TinyStyleEvent(
            context: String(context.suffix(280)),
            completion: completion,
            language: language,
            createdAt: Date()
        )
        try? await eventLogger.append(event: event)
    }

    // MARK: - Private

    private func maybeTrainStep() async -> TinyStyleTrainingMetrics? {
        guard acceptedSinceLastStep >= 10 else {
            return nil
        }
        acceptedSinceLastStep = 0
        return await trainStep()
    }

    private func trainStep() async -> TinyStyleTrainingMetrics? {
        let batch = await replayBuffer.sampleMixed(batchSize: 16)
        guard !batch.isEmpty else {
            return nil
        }

        let losses = await model.train(on: batch)
        let step = await model.trainingSteps()
        let metrics = TinyStyleTrainingMetrics(
            step: step,
            lossBefore: losses.lossBefore,
            lossAfter: losses.lossAfter,
            batchSize: batch.count
        )
        latestMetrics = metrics

        if step % 200 == 0 {
            try? await model.save()
            try? await replayBuffer.save()
        }

        return metrics
    }

    private func importKeyboardEvents() async {
        let events = (try? await eventLogger.drainEvents(limit: 600)) ?? []
        guard !events.isEmpty else {
            return
        }

        let examples = events.compactMap { event in
            TinyStyleTokenizer.makeExample(
                context: event.context,
                completion: event.completion,
                language: event.language
            )
        }

        guard !examples.isEmpty else {
            return
        }

        await replayBuffer.add(examples)
        acceptedSinceLastStep += examples.count
    }
}
