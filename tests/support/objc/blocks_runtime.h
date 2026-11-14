#ifndef VC_TEST_BLOCKS_RUNTIME_H
#define VC_TEST_BLOCKS_RUNTIME_H
extern void *_Block_copy(const void *block);
extern void _Block_release(const void *block);
#ifndef Block_copy
#define Block_copy(block) ((__typeof__(block))_Block_copy((const void *)(block)))
#endif
#ifndef Block_release
#define Block_release(block) _Block_release((const void *)(block))
#endif
#endif
