// PeekKit: single raw coder only; caller validates properties/dictionary and output budget first.
#include "lzma.h"
#include <stdlib.h>
static inline int peek_lzma_decode(int lzma2, const uint8_t *props, size_t propsSize,
 const uint8_t *input, size_t inputSize, uint8_t *output, size_t outputSize) {
 lzma_filter filters[2] = {{lzma2 ? LZMA_FILTER_LZMA2 : LZMA_FILTER_LZMA1, NULL}, {LZMA_VLI_UNKNOWN, NULL}};
 lzma_ret result = lzma_properties_decode(&filters[0], NULL, props, propsSize);
 if (result != LZMA_OK) return (int)result;
 if (!lzma2) {
  lzma_options_lzma *options = (lzma_options_lzma *)filters[0].options;
  options->ext_flags = LZMA_LZMA1EXT_ALLOW_EOPM;
  lzma_set_ext_size(*options, outputSize);
  filters[0].id = LZMA_FILTER_LZMA1EXT;
 }
 // Defense in depth: includes probability tables and dictionary, not a process RSS ceiling.
 if (lzma_raw_decoder_memusage(filters) > 16 * 1024 * 1024) { free(filters[0].options); return (int)LZMA_MEMLIMIT_ERROR; }
 size_t inPos = 0, outPos = 0;
 result = lzma_raw_buffer_decode(filters, NULL, input, &inPos, inputSize, output, &outPos, outputSize);
 free(filters[0].options);
 return result == LZMA_OK && inPos == inputSize && outPos == outputSize ? 0 : -1;
}
