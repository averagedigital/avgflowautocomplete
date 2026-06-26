#import "AILlamaRuntimeShim.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import <sys/param.h>

#include "llama.h"

typedef void (*ai_llama_backend_init_fn)(void);
typedef struct llama_model_params (*ai_llama_model_default_params_fn)(void);
typedef struct llama_context_params (*ai_llama_context_default_params_fn)(void);
typedef struct llama_sampler_chain_params (*ai_llama_sampler_chain_default_params_fn)(void);
typedef struct llama_model * (*ai_llama_model_load_from_file_fn)(const char *, struct llama_model_params);
typedef void (*ai_llama_model_free_fn)(struct llama_model *);
typedef struct llama_context * (*ai_llama_init_from_model_fn)(struct llama_model *, struct llama_context_params);
typedef void (*ai_llama_free_fn)(struct llama_context *);
typedef const struct llama_vocab * (*ai_llama_model_get_vocab_fn)(const struct llama_model *);
typedef bool (*ai_llama_vocab_get_add_bos_fn)(const struct llama_vocab *);
typedef bool (*ai_llama_vocab_is_eog_fn)(const struct llama_vocab *, llama_token);
typedef int32_t (*ai_llama_tokenize_fn)(const struct llama_vocab *, const char *, int32_t, llama_token *, int32_t, bool, bool);
typedef int32_t (*ai_llama_token_to_piece_fn)(const struct llama_vocab *, llama_token, char *, int32_t, int32_t, bool);
typedef struct llama_batch (*ai_llama_batch_get_one_fn)(llama_token *, int32_t);
typedef int32_t (*ai_llama_decode_fn)(struct llama_context *, struct llama_batch);
typedef struct llama_sampler * (*ai_llama_sampler_chain_init_fn)(struct llama_sampler_chain_params);
typedef void (*ai_llama_sampler_chain_add_fn)(struct llama_sampler *, struct llama_sampler *);
typedef struct llama_sampler * (*ai_llama_sampler_init_top_k_fn)(int32_t);
typedef struct llama_sampler * (*ai_llama_sampler_init_top_p_fn)(float, size_t);
typedef struct llama_sampler * (*ai_llama_sampler_init_temp_fn)(float);
typedef struct llama_sampler * (*ai_llama_sampler_init_dist_fn)(uint32_t);
typedef llama_token (*ai_llama_sampler_sample_fn)(struct llama_sampler *, struct llama_context *, int32_t);
typedef void (*ai_llama_sampler_accept_fn)(struct llama_sampler *, llama_token);
typedef void (*ai_llama_sampler_free_fn)(struct llama_sampler *);
typedef llama_memory_t (*ai_llama_get_memory_fn)(const struct llama_context *);
typedef void (*ai_llama_memory_clear_fn)(llama_memory_t, bool);

typedef struct AILlamaSymbols {
    ai_llama_backend_init_fn backend_init;
    ai_llama_model_default_params_fn model_default_params;
    ai_llama_context_default_params_fn context_default_params;
    ai_llama_sampler_chain_default_params_fn sampler_chain_default_params;
    ai_llama_model_load_from_file_fn model_load_from_file;
    ai_llama_model_free_fn model_free;
    ai_llama_init_from_model_fn init_from_model;
    ai_llama_free_fn free_context;
    ai_llama_model_get_vocab_fn model_get_vocab;
    ai_llama_vocab_get_add_bos_fn vocab_get_add_bos;
    ai_llama_vocab_is_eog_fn vocab_is_eog;
    ai_llama_tokenize_fn tokenize;
    ai_llama_token_to_piece_fn token_to_piece;
    ai_llama_batch_get_one_fn batch_get_one;
    ai_llama_decode_fn decode;
    ai_llama_sampler_chain_init_fn sampler_chain_init;
    ai_llama_sampler_chain_add_fn sampler_chain_add;
    ai_llama_sampler_init_top_k_fn sampler_init_top_k;
    ai_llama_sampler_init_top_p_fn sampler_init_top_p;
    ai_llama_sampler_init_temp_fn sampler_init_temp;
    ai_llama_sampler_init_dist_fn sampler_init_dist;
    ai_llama_sampler_sample_fn sampler_sample;
    ai_llama_sampler_accept_fn sampler_accept;
    ai_llama_sampler_free_fn sampler_free;
    ai_llama_get_memory_fn get_memory;
    ai_llama_memory_clear_fn memory_clear;
} AILlamaSymbols;

struct AILlamaRuntimeHandle {
    void * libraryHandles[5];
    AILlamaSymbols symbols;
    struct llama_model * model;
    struct llama_context * context;
    const struct llama_vocab * vocab;
    size_t memoryUsage;
    int32_t contextSize;
    char libraryDirectory[PATH_MAX];
};

static dispatch_once_t aiLlamaBackendInitOnce;
static NSString * const AILlamaEnvDirectoryKey = @"AICOMPLETE_LLAMA_DYLIB_DIR";

static void AIWriteError(char * buffer, size_t length, NSString * message) {
    if (buffer == NULL || length == 0) {
        return;
    }

    NSString * resolved = message ?: @"Unknown llama.cpp runtime error.";
    NSData * data = [resolved dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    size_t copyLength = MIN((size_t)data.length, length - 1);
    memcpy(buffer, data.bytes, copyLength);
    buffer[copyLength] = '\0';
}

static NSArray<NSString *> * AILlamaCandidateDirectories(void) {
    NSMutableArray<NSString *> * directories = [NSMutableArray array];

    NSString * envDirectory = NSProcessInfo.processInfo.environment[AILlamaEnvDirectoryKey];
    if (envDirectory.length > 0) {
        [directories addObject:envDirectory];
    }

    NSString * privateFrameworksPath = NSBundle.mainBundle.privateFrameworksPath;
    if (privateFrameworksPath.length > 0) {
        [directories addObject:privateFrameworksPath];
    }

    [directories addObject:@"/opt/homebrew/lib"];
    [directories addObject:@"/usr/local/lib"];

    return directories;
}

static NSString * AIResolveRuntimeDirectory(void) {
    NSFileManager * fileManager = NSFileManager.defaultManager;
    for (NSString * directory in AILlamaCandidateDirectories()) {
        NSString * candidate = [directory stringByAppendingPathComponent:@"libllama.0.dylib"];
        if ([fileManager fileExistsAtPath:candidate]) {
            return directory;
        }

        candidate = [directory stringByAppendingPathComponent:@"libllama.dylib"];
        if ([fileManager fileExistsAtPath:candidate]) {
            return directory;
        }
    }

    return nil;
}

static bool AILoadLibraryCandidates(AILlamaRuntimeHandle * handle, NSString * directory, NSArray<NSString *> * fileNames, int index, char * errorBuffer, size_t errorBufferLength) {
    NSFileManager * fileManager = NSFileManager.defaultManager;

    for (NSString * fileName in fileNames) {
        NSString * fullPath = [directory stringByAppendingPathComponent:fileName];
        if (![fileManager fileExistsAtPath:fullPath]) {
            continue;
        }

        void * libraryHandle = dlopen(fullPath.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        if (libraryHandle == NULL) {
            NSString * reason = [NSString stringWithFormat:@"Failed to load %@: %s", fileName, dlerror() ?: "unknown dlopen error"];
            AIWriteError(errorBuffer, errorBufferLength, reason);
            return false;
        }

        handle->libraryHandles[index] = libraryHandle;
        return true;
    }

    AIWriteError(errorBuffer, errorBufferLength, [NSString stringWithFormat:@"Missing required llama runtime library in %@.", directory]);
    return false;
}

static bool AIResolveSymbols(AILlamaRuntimeHandle * handle, char * errorBuffer, size_t errorBufferLength) {
#define AI_RESOLVE(symbolField, symbolName) do { \
    handle->symbols.symbolField = (ai_##symbolName##_fn)dlsym(handle->libraryHandles[4], #symbolName); \
    if (handle->symbols.symbolField == NULL) { \
        AIWriteError(errorBuffer, errorBufferLength, [NSString stringWithFormat:@"Missing llama symbol: %s", #symbolName]); \
        return false; \
    } \
} while (0)

    AI_RESOLVE(backend_init, llama_backend_init);
    AI_RESOLVE(model_default_params, llama_model_default_params);
    AI_RESOLVE(context_default_params, llama_context_default_params);
    AI_RESOLVE(sampler_chain_default_params, llama_sampler_chain_default_params);
    AI_RESOLVE(model_load_from_file, llama_model_load_from_file);
    AI_RESOLVE(model_free, llama_model_free);
    AI_RESOLVE(init_from_model, llama_init_from_model);
    AI_RESOLVE(free_context, llama_free);
    AI_RESOLVE(model_get_vocab, llama_model_get_vocab);
    AI_RESOLVE(vocab_get_add_bos, llama_vocab_get_add_bos);
    AI_RESOLVE(vocab_is_eog, llama_vocab_is_eog);
    AI_RESOLVE(tokenize, llama_tokenize);
    AI_RESOLVE(token_to_piece, llama_token_to_piece);
    AI_RESOLVE(batch_get_one, llama_batch_get_one);
    AI_RESOLVE(decode, llama_decode);
    AI_RESOLVE(sampler_chain_init, llama_sampler_chain_init);
    AI_RESOLVE(sampler_chain_add, llama_sampler_chain_add);
    AI_RESOLVE(sampler_init_top_k, llama_sampler_init_top_k);
    AI_RESOLVE(sampler_init_top_p, llama_sampler_init_top_p);
    AI_RESOLVE(sampler_init_temp, llama_sampler_init_temp);
    AI_RESOLVE(sampler_init_dist, llama_sampler_init_dist);
    AI_RESOLVE(sampler_sample, llama_sampler_sample);
    AI_RESOLVE(sampler_accept, llama_sampler_accept);
    AI_RESOLVE(sampler_free, llama_sampler_free);
    AI_RESOLVE(get_memory, llama_get_memory);
    AI_RESOLVE(memory_clear, llama_memory_clear);

#undef AI_RESOLVE
    return true;
}

static void AIUnloadLibraries(AILlamaRuntimeHandle * handle) {
    for (NSInteger index = 4; index >= 0; index -= 1) {
        if (handle->libraryHandles[index] != NULL) {
            dlclose(handle->libraryHandles[index]);
            handle->libraryHandles[index] = NULL;
        }
    }
}

static void AIResetModelState(AILlamaRuntimeHandle * handle) {
    if (handle->context != NULL) {
        handle->symbols.free_context(handle->context);
        handle->context = NULL;
    }

    if (handle->model != NULL) {
        handle->symbols.model_free(handle->model);
        handle->model = NULL;
    }

    handle->vocab = NULL;
    handle->memoryUsage = 0;
    handle->contextSize = 0;
}

static struct llama_sampler * AICreateSampler(const AILlamaSymbols * symbols, float temperature, float topP, uint32_t seed) {
    struct llama_sampler_chain_params chainParams = symbols->sampler_chain_default_params();
    struct llama_sampler * chain = symbols->sampler_chain_init(chainParams);
    if (chain == NULL) {
        return NULL;
    }

    symbols->sampler_chain_add(chain, symbols->sampler_init_top_k(40));
    symbols->sampler_chain_add(chain, symbols->sampler_init_top_p(MAX(0.1f, topP), 1));
    symbols->sampler_chain_add(chain, symbols->sampler_init_temp(MAX(0.0f, temperature)));
    symbols->sampler_chain_add(chain, symbols->sampler_init_dist(seed));
    return chain;
}

bool AILlamaInProcessRuntimeIsAvailable(void) {
    return AIResolveRuntimeDirectory() != nil;
}

AILlamaRuntimeHandleRef AILlamaRuntimeCreate(char * errorBuffer, size_t errorBufferLength) {
    NSString * runtimeDirectory = AIResolveRuntimeDirectory();
    if (runtimeDirectory.length == 0) {
        AIWriteError(errorBuffer, errorBufferLength, @"Bundled llama.cpp dylibs were not found.");
        return NULL;
    }

    AILlamaRuntimeHandle * handle = (AILlamaRuntimeHandle *)calloc(1, sizeof(AILlamaRuntimeHandle));
    if (handle == NULL) {
        AIWriteError(errorBuffer, errorBufferLength, @"Failed to allocate llama runtime handle.");
        return NULL;
    }

    strlcpy(handle->libraryDirectory, runtimeDirectory.fileSystemRepresentation, sizeof(handle->libraryDirectory));

    NSArray<NSString *> * requiredLibraries[] = {
        @[ @"libggml-base.0.dylib", @"libggml-base.dylib" ],
        @[ @"libggml-blas.0.dylib", @"libggml-blas.dylib" ],
        @[ @"libggml-cpu.0.dylib", @"libggml-cpu.dylib" ],
        @[ @"libggml.0.dylib", @"libggml.dylib" ],
        @[ @"libllama.0.dylib", @"libllama.dylib" ],
    };

    for (int index = 0; index < 5; index += 1) {
        if (!AILoadLibraryCandidates(handle, runtimeDirectory, requiredLibraries[index], index, errorBuffer, errorBufferLength)) {
            AIUnloadLibraries(handle);
            free(handle);
            return NULL;
        }
    }

    if (!AIResolveSymbols(handle, errorBuffer, errorBufferLength)) {
        AIUnloadLibraries(handle);
        free(handle);
        return NULL;
    }

    dispatch_once(&aiLlamaBackendInitOnce, ^{
        handle->symbols.backend_init();
    });

    return (AILlamaRuntimeHandleRef)handle;
}

bool AILlamaRuntimeLoadModel(AILlamaRuntimeHandleRef opaqueHandle, const char * modelPath, int32_t contextSize, int32_t threadCount, char * errorBuffer, size_t errorBufferLength) {
    AILlamaRuntimeHandle * handle = (AILlamaRuntimeHandle *)opaqueHandle;
    if (handle == NULL || modelPath == NULL) {
        AIWriteError(errorBuffer, errorBufferLength, @"llama runtime handle is invalid.");
        return false;
    }

    AIResetModelState(handle);

    struct llama_model_params modelParams = handle->symbols.model_default_params();
    modelParams.use_mmap = true;
    modelParams.use_mlock = false;
    modelParams.n_gpu_layers = 0;
    modelParams.check_tensors = false;

    struct llama_model * model = handle->symbols.model_load_from_file(modelPath, modelParams);
    if (model == NULL) {
        AIWriteError(errorBuffer, errorBufferLength, @"Failed to load GGUF model into in-process llama runtime.");
        return false;
    }

    struct llama_context_params contextParams = handle->symbols.context_default_params();
    const int32_t resolvedContextSize = MAX(512, contextSize);
    const int32_t resolvedThreadCount = MAX(1, threadCount);
    contextParams.n_ctx = (uint32_t)resolvedContextSize;
    contextParams.n_batch = (uint32_t)resolvedContextSize;
    contextParams.n_threads = resolvedThreadCount;
    contextParams.n_threads_batch = resolvedThreadCount;
    contextParams.offload_kqv = false;
    contextParams.no_perf = true;

    struct llama_context * context = handle->symbols.init_from_model(model, contextParams);
    if (context == NULL) {
        handle->symbols.model_free(model);
        AIWriteError(errorBuffer, errorBufferLength, @"Failed to create llama context for the selected model.");
        return false;
    }

    handle->model = model;
    handle->context = context;
    handle->vocab = handle->symbols.model_get_vocab(model);
    handle->contextSize = resolvedContextSize;

    NSNumber * fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:[NSString stringWithUTF8String:modelPath] error:nil] objectForKey:NSFileSize];
    handle->memoryUsage = fileSize.unsignedLongLongValue;
    return true;
}

void AILlamaRuntimeUnloadModel(AILlamaRuntimeHandleRef opaqueHandle) {
    AILlamaRuntimeHandle * handle = (AILlamaRuntimeHandle *)opaqueHandle;
    if (handle == NULL) {
        return;
    }
    AIResetModelState(handle);
}

char * AILlamaRuntimeGenerate(AILlamaRuntimeHandleRef opaqueHandle, const char * prompt, int32_t maxTokens, uint32_t seed, float temperature, float topP, char * errorBuffer, size_t errorBufferLength) {
    AILlamaRuntimeHandle * handle = (AILlamaRuntimeHandle *)opaqueHandle;
    if (handle == NULL || handle->context == NULL || handle->model == NULL || handle->vocab == NULL) {
        AIWriteError(errorBuffer, errorBufferLength, @"Local model is not loaded in the in-process runtime.");
        return NULL;
    }

    if (prompt == NULL || maxTokens <= 0) {
        AIWriteError(errorBuffer, errorBufferLength, @"Prompt or maxTokens is invalid.");
        return NULL;
    }

    NSString * promptString = [NSString stringWithUTF8String:prompt] ?: @"";
    NSData * promptData = [promptString dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES] ?: [NSData data];

    llama_memory_t memory = handle->symbols.get_memory(handle->context);
    if (memory != NULL) {
        handle->symbols.memory_clear(memory, false);
    }

    const bool addBos = handle->symbols.vocab_get_add_bos(handle->vocab);
    int32_t tokenCapacity = MAX((int32_t)promptData.length + 32, handle->contextSize);
    NSMutableData * tokenData = [NSMutableData dataWithLength:(NSUInteger)tokenCapacity * sizeof(llama_token)];
    llama_token * tokens = (llama_token *)tokenData.mutableBytes;

    int32_t tokenCount = handle->symbols.tokenize(
        handle->vocab,
        (const char *)promptData.bytes,
        (int32_t)promptData.length,
        tokens,
        tokenCapacity,
        addBos,
        false
    );

    if (tokenCount < 0) {
        tokenCapacity = -tokenCount;
        tokenData.length = (NSUInteger)tokenCapacity * sizeof(llama_token);
        tokens = (llama_token *)tokenData.mutableBytes;
        tokenCount = handle->symbols.tokenize(
            handle->vocab,
            (const char *)promptData.bytes,
            (int32_t)promptData.length,
            tokens,
            tokenCapacity,
            addBos,
            false
        );
    }

    if (tokenCount <= 0) {
        AIWriteError(errorBuffer, errorBufferLength, @"Failed to tokenize prompt for local inference.");
        return NULL;
    }

    if (tokenCount >= handle->contextSize - 8) {
        const int32_t keepCount = MAX(1, handle->contextSize - 32);
        memmove(tokens, tokens + (tokenCount - keepCount), (size_t)keepCount * sizeof(llama_token));
        tokenCount = keepCount;
    }

    struct llama_batch batch = handle->symbols.batch_get_one(tokens, tokenCount);
    if (handle->symbols.decode(handle->context, batch) != 0) {
        AIWriteError(errorBuffer, errorBufferLength, @"Initial prompt decode failed in the in-process llama runtime.");
        return NULL;
    }

    struct llama_sampler * sampler = AICreateSampler(&handle->symbols, temperature, topP, seed);
    if (sampler == NULL) {
        AIWriteError(errorBuffer, errorBufferLength, @"Failed to create llama sampler chain.");
        return NULL;
    }

    NSMutableData * outputData = [NSMutableData data];

    for (int32_t index = 0; index < maxTokens; index += 1) {
        llama_token token = handle->symbols.sampler_sample(sampler, handle->context, -1);
        if (handle->symbols.vocab_is_eog(handle->vocab, token)) {
            break;
        }

        handle->symbols.sampler_accept(sampler, token);

        char pieceBuffer[256];
        int32_t pieceLength = handle->symbols.token_to_piece(handle->vocab, token, pieceBuffer, (int32_t)sizeof(pieceBuffer), 0, false);
        if (pieceLength < 0 && pieceLength != INT32_MIN) {
            NSMutableData * dynamicPiece = [NSMutableData dataWithLength:(NSUInteger)(-pieceLength) + 1];
            pieceLength = handle->symbols.token_to_piece(handle->vocab, token, (char *)dynamicPiece.mutableBytes, (int32_t)dynamicPiece.length, 0, false);
            if (pieceLength > 0) {
                [outputData appendBytes:dynamicPiece.bytes length:(NSUInteger)pieceLength];
            }
        } else if (pieceLength > 0) {
            [outputData appendBytes:pieceBuffer length:(NSUInteger)pieceLength];
        }

        llama_token nextToken = token;
        struct llama_batch nextBatch = handle->symbols.batch_get_one(&nextToken, 1);
        if (handle->symbols.decode(handle->context, nextBatch) != 0) {
            handle->symbols.sampler_free(sampler);
            AIWriteError(errorBuffer, errorBufferLength, @"Token decode failed in the in-process llama runtime.");
            return NULL;
        }
    }

    handle->symbols.sampler_free(sampler);

    char * result = (char *)calloc(outputData.length + 1, sizeof(char));
    if (result == NULL) {
        AIWriteError(errorBuffer, errorBufferLength, @"Failed to allocate output buffer for local inference result.");
        return NULL;
    }

    if (outputData.length > 0) {
        memcpy(result, outputData.bytes, outputData.length);
    }
    result[outputData.length] = '\0';
    return result;
}

size_t AILlamaRuntimeMemoryUsage(AILlamaRuntimeHandleRef opaqueHandle) {
    AILlamaRuntimeHandle * handle = (AILlamaRuntimeHandle *)opaqueHandle;
    return handle != NULL ? handle->memoryUsage : 0;
}

void AILlamaRuntimeDestroy(AILlamaRuntimeHandleRef opaqueHandle) {
    AILlamaRuntimeHandle * handle = (AILlamaRuntimeHandle *)opaqueHandle;
    if (handle == NULL) {
        return;
    }

    AIResetModelState(handle);
    AIUnloadLibraries(handle);
    free(handle);
}

void AILlamaStringFree(char * stringPointer) {
    free(stringPointer);
}
