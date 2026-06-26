#import <stdbool.h>
#import <stddef.h>
#import <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void * AILlamaRuntimeHandleRef;

bool AILlamaInProcessRuntimeIsAvailable(void);
AILlamaRuntimeHandleRef AILlamaRuntimeCreate(char * errorBuffer, size_t errorBufferLength);
bool AILlamaRuntimeLoadModel(AILlamaRuntimeHandleRef handle, const char * modelPath, int32_t contextSize, int32_t threadCount, char * errorBuffer, size_t errorBufferLength);
void AILlamaRuntimeUnloadModel(AILlamaRuntimeHandleRef handle);
char * AILlamaRuntimeGenerate(AILlamaRuntimeHandleRef handle, const char * prompt, int32_t maxTokens, uint32_t seed, float temperature, float topP, char * errorBuffer, size_t errorBufferLength);
size_t AILlamaRuntimeMemoryUsage(AILlamaRuntimeHandleRef handle);
void AILlamaRuntimeDestroy(AILlamaRuntimeHandleRef handle);
void AILlamaStringFree(char * stringPointer);

#ifdef __cplusplus
}
#endif
