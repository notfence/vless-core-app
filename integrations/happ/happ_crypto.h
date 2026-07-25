#ifndef VLESS_CORE_HAPP_CRYPTO_H
#define VLESS_CORE_HAPP_CRYPTO_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int VCHappIsEncryptedLink(const char *link);

/*
 * Returns 1 on success, 0 when link is not a supported HAPP encrypted link,
 * and -1 when the link is recognized but malformed or cannot be decrypted.
 * The caller owns
 * *plaintextOut and must release it with VCHappFreePlaintext().
 */
int VCHappDecryptLink(const char *link,
                      unsigned char **plaintextOut,
                      size_t *plaintextLengthOut,
                      char *modeOut,
                      size_t modeCapacity,
                      char *errorOut,
                      size_t errorCapacity);

void VCHappFreePlaintext(void *plaintext);

#ifdef __cplusplus
}
#endif

#endif
