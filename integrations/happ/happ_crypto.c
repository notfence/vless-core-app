#include "happ_crypto.h"

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/rsa.h>

#include <ctype.h>
#include <limits.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static const char kHappCrypt4Prefix[] = "happ://crypt4/";
static const char kHappCrypt5Prefix[] = "happ://crypt5/";

typedef struct {
    const char *marker;
    const char *privateKeyBase64;
} VCHappCrypt5Key;

#include "happ_crypt5_keys.inc"
#include "happ_crypt4_key.inc"

static void SetError(char *errorOut, size_t errorCapacity, const char *format, ...) {
    if (!errorOut || errorCapacity == 0) return;

    va_list args;
    va_start(args, format);
    vsnprintf(errorOut, errorCapacity, format, args);
    va_end(args);
    errorOut[errorCapacity - 1] = '\0';
}

static void SetOpenSSLError(char *errorOut, size_t errorCapacity, const char *fallback) {
    unsigned long code = ERR_get_error();
    if (code == 0) {
        SetError(errorOut, errorCapacity, "%s", fallback);
        return;
    }

    char detail[160];
    ERR_error_string_n(code, detail, sizeof(detail));
    SetError(errorOut, errorCapacity, "%s: %s", fallback, detail);
}

static int DecodeBase64(const char *input,
                        unsigned char **decodedOut,
                        size_t *decodedLengthOut,
                        char *errorOut,
                        size_t errorCapacity) {
    size_t inputLength;
    char *normalized = NULL;
    unsigned char *decoded = NULL;
    size_t normalizedLength = 0;
    size_t i;
    int decodedLength;
    size_t padding = 0;

    if (decodedOut) *decodedOut = NULL;
    if (decodedLengthOut) *decodedLengthOut = 0;
    if (!input || !decodedOut || !decodedLengthOut) {
        SetError(errorOut, errorCapacity, "invalid base64 input");
        return 0;
    }

    inputLength = strlen(input);
    normalized = (char *)malloc(inputLength + 4);
    if (!normalized) {
        SetError(errorOut, errorCapacity, "out of memory");
        return 0;
    }

    for (i = 0; i < inputLength; i++) {
        unsigned char c = (unsigned char)input[i];
        if (isspace(c)) continue;
        if (c == '=') continue;
        if (c == '-') c = '+';
        if (c == '_') c = '/';
        if (!isalnum(c) && c != '+' && c != '/') {
            free(normalized);
            SetError(errorOut, errorCapacity, "invalid base64 character");
            return 0;
        }
        normalized[normalizedLength++] = (char)c;
    }

    if (normalizedLength == 0 || normalizedLength % 4 == 1) {
        free(normalized);
        SetError(errorOut, errorCapacity, "invalid base64 length");
        return 0;
    }

    padding = (4 - (normalizedLength % 4)) % 4;
    while (padding > 0) {
        normalized[normalizedLength++] = '=';
        padding--;
    }
    normalized[normalizedLength] = '\0';

    decoded = (unsigned char *)malloc((normalizedLength / 4) * 3 + 1);
    if (!decoded) {
        free(normalized);
        SetError(errorOut, errorCapacity, "out of memory");
        return 0;
    }

    decodedLength = EVP_DecodeBlock(decoded,
                                    (const unsigned char *)normalized,
                                    (int)normalizedLength);
    if (decodedLength < 0) {
        free(decoded);
        free(normalized);
        SetError(errorOut, errorCapacity, "invalid base64 data");
        return 0;
    }

    if (normalizedLength >= 1 && normalized[normalizedLength - 1] == '=') decodedLength--;
    if (normalizedLength >= 2 && normalized[normalizedLength - 2] == '=') decodedLength--;
    free(normalized);

    if (decodedLength <= 0) {
        free(decoded);
        SetError(errorOut, errorCapacity, "base64 data is empty");
        return 0;
    }

    decoded[decodedLength] = '\0';
    *decodedOut = decoded;
    *decodedLengthOut = (size_t)decodedLength;
    return 1;
}

static int VCHappIsCrypt4Link(const char *link) {
    size_t prefixLength = sizeof(kHappCrypt4Prefix) - 1;
    return link && strncasecmp(link, kHappCrypt4Prefix, prefixLength) == 0;
}

int VCHappIsEncryptedLink(const char *link) {
    size_t crypt4PrefixLength = sizeof(kHappCrypt4Prefix) - 1;
    size_t crypt5PrefixLength = sizeof(kHappCrypt5Prefix) - 1;
    if (!link) return 0;
    return strncasecmp(link, kHappCrypt4Prefix, crypt4PrefixLength) == 0 ||
           strncasecmp(link, kHappCrypt5Prefix, crypt5PrefixLength) == 0;
}

int VCHappDecryptCrypt4Link(const char *link,
                            unsigned char **plaintextOut,
                            size_t *plaintextLengthOut,
                            char *errorOut,
                            size_t errorCapacity) {
    size_t prefixLength = sizeof(kHappCrypt4Prefix) - 1;
    unsigned char *keyDER = NULL;
    size_t keyDERLength = 0;
    unsigned char *ciphertext = NULL;
    size_t ciphertextLength = 0;
    unsigned char *plaintext = NULL;
    size_t plaintextLength = 0;
    const unsigned char *keyCursor;
    EVP_PKEY *key = NULL;
    size_t blockSize;
    size_t offset;
    int result = -1;

    if (plaintextOut) *plaintextOut = NULL;
    if (plaintextLengthOut) *plaintextLengthOut = 0;
    if (errorOut && errorCapacity > 0) errorOut[0] = '\0';

    if (!VCHappIsCrypt4Link(link)) return 0;
    if (!plaintextOut || !plaintextLengthOut) {
        SetError(errorOut, errorCapacity, "invalid output buffer");
        return -1;
    }

    if (!DecodeBase64(kHappCrypt4PrivateKeyBase64,
                      &keyDER,
                      &keyDERLength,
                      errorOut,
                      errorCapacity)) {
        goto cleanup;
    }

    keyCursor = keyDER;
    key = d2i_PrivateKey(EVP_PKEY_RSA, NULL, &keyCursor, (long)keyDERLength);
    if (!key || keyCursor != keyDER + keyDERLength) {
        SetOpenSSLError(errorOut, errorCapacity, "cannot load happ crypt4 key");
        goto cleanup;
    }

    if (!DecodeBase64(link + prefixLength,
                      &ciphertext,
                      &ciphertextLength,
                      errorOut,
                      errorCapacity)) {
        goto cleanup;
    }

    blockSize = (size_t)EVP_PKEY_get_size(key);
    if (blockSize == 0 || ciphertextLength % blockSize != 0) {
        SetError(errorOut,
                 errorCapacity,
                 "encrypted payload length %lu is not a multiple of RSA block %lu",
                 (unsigned long)ciphertextLength,
                 (unsigned long)blockSize);
        goto cleanup;
    }

    plaintext = (unsigned char *)malloc(ciphertextLength + 1);
    if (!plaintext) {
        SetError(errorOut, errorCapacity, "out of memory");
        goto cleanup;
    }

    for (offset = 0; offset < ciphertextLength; offset += blockSize) {
        EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(key, NULL);
        size_t chunkLength = blockSize;
        if (!ctx ||
            EVP_PKEY_decrypt_init(ctx) <= 0 ||
            EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_PKCS1_PADDING) <= 0 ||
            EVP_PKEY_decrypt(ctx,
                             plaintext + plaintextLength,
                             &chunkLength,
                             ciphertext + offset,
                             blockSize) <= 0) {
            if (ctx) EVP_PKEY_CTX_free(ctx);
            SetOpenSSLError(errorOut, errorCapacity, "happ crypt4 decryption failed");
            goto cleanup;
        }
        EVP_PKEY_CTX_free(ctx);
        plaintextLength += chunkLength;
    }

    plaintext[plaintextLength] = '\0';
    *plaintextOut = plaintext;
    *plaintextLengthOut = plaintextLength;
    plaintext = NULL;
    result = 1;

cleanup:
    if (plaintext) free(plaintext);
    if (ciphertext) free(ciphertext);
    if (key) EVP_PKEY_free(key);
    if (keyDER) free(keyDER);
    return result;
}

static char *CopyStringRange(const char *value, size_t offset, size_t length) {
    char *result;
    if (!value) return NULL;
    result = (char *)malloc(length + 1);
    if (!result) return NULL;
    memcpy(result, value + offset, length);
    result[length] = '\0';
    return result;
}

static void SwapCharacterPairs(char *value, size_t length) {
    size_t i;
    if (!value) return;
    for (i = 0; i + 1 < length; i += 2) {
        char tmp = value[i];
        value[i] = value[i + 1];
        value[i + 1] = tmp;
    }
}

static void SwapFourCharacterHalves(char *value, size_t length) {
    size_t i;
    if (!value) return;
    for (i = 0; i + 3 < length; i += 4) {
        char first = value[i];
        char second = value[i + 1];
        value[i] = value[i + 2];
        value[i + 1] = value[i + 3];
        value[i + 2] = first;
        value[i + 3] = second;
    }
}

static const char *Crypt5PrivateKeyForMarker(const char marker[9]) {
    size_t i;
    for (i = 0; i < sizeof(kHappCrypt5Keys) / sizeof(kHappCrypt5Keys[0]); i++) {
        if (strcmp(marker, kHappCrypt5Keys[i].marker) == 0) {
            return kHappCrypt5Keys[i].privateKeyBase64;
        }
    }
    return NULL;
}

static int RSADecryptSingleBlock(const char *privateKeyBase64,
                                 const char *ciphertextBase64,
                                 unsigned char **plaintextOut,
                                 size_t *plaintextLengthOut,
                                 char *errorOut,
                                 size_t errorCapacity) {
    unsigned char *keyDER = NULL;
    size_t keyDERLength = 0;
    unsigned char *ciphertext = NULL;
    size_t ciphertextLength = 0;
    unsigned char *plaintext = NULL;
    const unsigned char *keyCursor;
    EVP_PKEY *key = NULL;
    EVP_PKEY_CTX *ctx = NULL;
    size_t plaintextLength = 0;
    int success = 0;

    if (plaintextOut) *plaintextOut = NULL;
    if (plaintextLengthOut) *plaintextLengthOut = 0;
    if (!privateKeyBase64 || !ciphertextBase64 || !plaintextOut || !plaintextLengthOut) {
        SetError(errorOut, errorCapacity, "invalid RSA input");
        return 0;
    }

    if (!DecodeBase64(privateKeyBase64, &keyDER, &keyDERLength, errorOut, errorCapacity) ||
        !DecodeBase64(ciphertextBase64, &ciphertext, &ciphertextLength, errorOut, errorCapacity)) {
        goto cleanup;
    }

    ERR_clear_error();
    keyCursor = keyDER;
    key = d2i_AutoPrivateKey(NULL, &keyCursor, (long)keyDERLength);
    if (!key || keyCursor != keyDER + keyDERLength) {
        SetOpenSSLError(errorOut, errorCapacity, "cannot load HAPP private key");
        goto cleanup;
    }

    plaintextLength = (size_t)EVP_PKEY_get_size(key);
    plaintext = (unsigned char *)malloc(plaintextLength + 1);
    if (!plaintext) {
        SetError(errorOut, errorCapacity, "out of memory");
        goto cleanup;
    }

    ctx = EVP_PKEY_CTX_new(key, NULL);
    if (!ctx ||
        EVP_PKEY_decrypt_init(ctx) <= 0 ||
        EVP_PKEY_CTX_set_rsa_padding(ctx, RSA_PKCS1_PADDING) <= 0 ||
        EVP_PKEY_decrypt(ctx, plaintext, &plaintextLength, ciphertext, ciphertextLength) <= 0) {
        SetOpenSSLError(errorOut, errorCapacity, "HAPP RSA decryption failed");
        goto cleanup;
    }

    plaintext[plaintextLength] = '\0';
    *plaintextOut = plaintext;
    *plaintextLengthOut = plaintextLength;
    plaintext = NULL;
    success = 1;

cleanup:
    if (ctx) EVP_PKEY_CTX_free(ctx);
    if (key) EVP_PKEY_free(key);
    if (plaintext) free(plaintext);
    if (ciphertext) free(ciphertext);
    if (keyDER) free(keyDER);
    return success;
}

static int ChaCha20Poly1305Decrypt(const unsigned char key[32],
                                   const unsigned char nonce[12],
                                   const unsigned char *ciphertextAndTag,
                                   size_t ciphertextAndTagLength,
                                   unsigned char **plaintextOut,
                                   size_t *plaintextLengthOut,
                                   char *errorOut,
                                   size_t errorCapacity) {
    EVP_CIPHER_CTX *ctx = NULL;
    unsigned char *plaintext = NULL;
    size_t ciphertextLength;
    int outputLength = 0;
    int finalLength = 0;
    int success = 0;

    if (plaintextOut) *plaintextOut = NULL;
    if (plaintextLengthOut) *plaintextLengthOut = 0;
    if (!key || !nonce || !ciphertextAndTag || ciphertextAndTagLength < 16 ||
        !plaintextOut || !plaintextLengthOut || ciphertextAndTagLength > (size_t)INT_MAX) {
        SetError(errorOut, errorCapacity, "invalid ChaCha20-Poly1305 input");
        return 0;
    }

    ciphertextLength = ciphertextAndTagLength - 16;
    plaintext = (unsigned char *)malloc(ciphertextLength + 1);
    ctx = EVP_CIPHER_CTX_new();
    ERR_clear_error();
    if (!plaintext || !ctx ||
        EVP_DecryptInit_ex(ctx, EVP_chacha20_poly1305(), NULL, NULL, NULL) <= 0 ||
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_AEAD_SET_IVLEN, 12, NULL) <= 0 ||
        EVP_DecryptInit_ex(ctx, NULL, NULL, key, nonce) <= 0 ||
        EVP_DecryptUpdate(ctx, plaintext, &outputLength, ciphertextAndTag, (int)ciphertextLength) <= 0 ||
        EVP_CIPHER_CTX_ctrl(ctx,
                            EVP_CTRL_AEAD_SET_TAG,
                            16,
                            (void *)(ciphertextAndTag + ciphertextLength)) <= 0 ||
        EVP_DecryptFinal_ex(ctx, plaintext + outputLength, &finalLength) <= 0) {
        if (!plaintext) {
            SetError(errorOut, errorCapacity, "out of memory");
        } else {
            SetOpenSSLError(errorOut, errorCapacity, "HAPP crypt5 authentication failed");
        }
        goto cleanup;
    }

    plaintext[outputLength + finalLength] = '\0';
    *plaintextOut = plaintext;
    *plaintextLengthOut = (size_t)(outputLength + finalLength);
    plaintext = NULL;
    success = 1;

cleanup:
    if (ctx) EVP_CIPHER_CTX_free(ctx);
    if (plaintext) free(plaintext);
    return success;
}

static int DecryptCrypt5Body(const char *body,
                             size_t bodyLength,
                             const char *privateKeyBase64,
                             int salted,
                             unsigned char **plaintextOut,
                             size_t *plaintextLengthOut,
                             char *errorOut,
                             size_t errorCapacity) {
    const size_t headerLength = salted ? 22 : 12;
    const char *rest;
    size_t restLength;
    size_t digitCount = 0;
    size_t segmentLength = 0;
    size_t packedLength;
    const char *packed;
    char *encryptedSegment = NULL;
    char *rsaSegment = NULL;
    unsigned char *rsaPlaintext = NULL;
    size_t rsaPlaintextLength = 0;
    unsigned char *rsaValue = NULL;
    size_t rsaValueLength = 0;
    unsigned char chachaKey[32];
    unsigned char *encryptedURL = NULL;
    size_t encryptedURLLength = 0;
    unsigned char *intermediate = NULL;
    size_t intermediateLength = 0;
    char *finalBase64 = NULL;
    unsigned char *plaintext = NULL;
    size_t plaintextLength = 0;
    size_t i;
    int success = 0;

    if (plaintextOut) *plaintextOut = NULL;
    if (plaintextLengthOut) *plaintextLengthOut = 0;
    if (!body || bodyLength < headerLength + 2) {
        SetError(errorOut, errorCapacity, "crypt5 header is truncated");
        return 0;
    }

    rest = body + headerLength;
    restLength = bodyLength - headerLength;
    while (digitCount < restLength && isdigit((unsigned char)rest[digitCount])) {
        size_t digit = (size_t)(rest[digitCount] - '0');
        if (segmentLength > (SIZE_MAX - digit) / 10) {
            SetError(errorOut, errorCapacity, "crypt5 segment length overflows");
            goto cleanup;
        }
        segmentLength = segmentLength * 10 + digit;
        digitCount++;
    }
    if (digitCount == 0 || digitCount >= restLength) {
        SetError(errorOut, errorCapacity, "crypt5 segment length is missing");
        goto cleanup;
    }

    packed = rest + digitCount;
    packedLength = restLength - digitCount;
    if (packedLength < 1 || segmentLength > packedLength - 1) {
        SetError(errorOut, errorCapacity, "crypt5 encrypted segment is truncated");
        goto cleanup;
    }

    encryptedSegment = CopyStringRange(packed, 1, segmentLength);
    rsaSegment = CopyStringRange(packed, 1 + segmentLength, packedLength - 1 - segmentLength);
    if (!encryptedSegment || !rsaSegment || rsaSegment[0] == '\0') {
        SetError(errorOut, errorCapacity, "out of memory or empty crypt5 RSA segment");
        goto cleanup;
    }

    if (!RSADecryptSingleBlock(privateKeyBase64,
                               rsaSegment,
                               &rsaPlaintext,
                               &rsaPlaintextLength,
                               errorOut,
                               errorCapacity)) {
        goto cleanup;
    }
    SwapCharacterPairs((char *)rsaPlaintext, rsaPlaintextLength);
    if (!DecodeBase64((const char *)rsaPlaintext,
                      &rsaValue,
                      &rsaValueLength,
                      errorOut,
                      errorCapacity) ||
        rsaValueLength != sizeof(chachaKey)) {
        SetError(errorOut, errorCapacity, "crypt5 ChaCha20 key has invalid length");
        goto cleanup;
    }

    for (i = 0; i < sizeof(chachaKey); i++) {
        chachaKey[i] = salted
                           ? (unsigned char)(rsaValue[i] ^ (unsigned char)body[14 + (i % 8)])
                           : rsaValue[i];
    }

    if (!DecodeBase64(encryptedSegment,
                      &encryptedURL,
                      &encryptedURLLength,
                      errorOut,
                      errorCapacity) ||
        !ChaCha20Poly1305Decrypt(chachaKey,
                                (const unsigned char *)body,
                                encryptedURL,
                                encryptedURLLength,
                                &intermediate,
                                &intermediateLength,
                                errorOut,
                                errorCapacity)) {
        goto cleanup;
    }

    finalBase64 = CopyStringRange((const char *)intermediate, 0, intermediateLength);
    if (!finalBase64) {
        SetError(errorOut, errorCapacity, "out of memory");
        goto cleanup;
    }
    SwapCharacterPairs(finalBase64, intermediateLength);
    if (!DecodeBase64(finalBase64, &plaintext, &plaintextLength, errorOut, errorCapacity)) {
        goto cleanup;
    }

    *plaintextOut = plaintext;
    *plaintextLengthOut = plaintextLength;
    plaintext = NULL;
    success = 1;

cleanup:
    memset(chachaKey, 0, sizeof(chachaKey));
    if (plaintext) free(plaintext);
    if (finalBase64) free(finalBase64);
    if (intermediate) free(intermediate);
    if (encryptedURL) free(encryptedURL);
    if (rsaValue) free(rsaValue);
    if (rsaPlaintext) free(rsaPlaintext);
    if (rsaSegment) free(rsaSegment);
    if (encryptedSegment) free(encryptedSegment);
    return success;
}

static int DecryptCrypt5Link(const char *link,
                             unsigned char **plaintextOut,
                             size_t *plaintextLengthOut,
                             char *errorOut,
                             size_t errorCapacity) {
    size_t prefixLength = sizeof(kHappCrypt5Prefix) - 1;
    const char *payload;
    size_t payloadLength;
    char *shuffled = NULL;
    char marker[9];
    const char *privateKeyBase64;
    const char *body;
    size_t bodyLength;
    int preferSalted;
    int attempts[2];
    char firstError[256];
    char secondError[256];
    int success = 0;

    if (plaintextOut) *plaintextOut = NULL;
    if (plaintextLengthOut) *plaintextLengthOut = 0;
    firstError[0] = '\0';
    secondError[0] = '\0';

    if (!link || strncasecmp(link, kHappCrypt5Prefix, prefixLength) != 0) return 0;
    payload = link + prefixLength;
    payloadLength = strlen(payload);
    if (payloadLength < 8) {
        SetError(errorOut, errorCapacity, "crypt5 payload is too short");
        return -1;
    }

    shuffled = CopyStringRange(payload, 0, payloadLength);
    if (!shuffled) {
        SetError(errorOut, errorCapacity, "out of memory");
        return -1;
    }
    SwapFourCharacterHalves(shuffled, payloadLength);

    memcpy(marker, shuffled, 4);
    memcpy(marker + 4, shuffled + payloadLength - 4, 4);
    marker[8] = '\0';
    privateKeyBase64 = Crypt5PrivateKeyForMarker(marker);
    if (!privateKeyBase64) {
        SetError(errorOut, errorCapacity, "unknown crypt5 key marker: %s", marker);
        goto cleanup;
    }

    body = shuffled + 4;
    bodyLength = payloadLength - 8;
    if (bodyLength < 13) {
        SetError(errorOut, errorCapacity, "crypt5 body is too short");
        goto cleanup;
    }

    preferSalted = !isdigit((unsigned char)body[12]);
    attempts[0] = preferSalted ? 1 : 0;
    attempts[1] = preferSalted ? 0 : 1;
    if (DecryptCrypt5Body(body,
                          bodyLength,
                          privateKeyBase64,
                          attempts[0],
                          plaintextOut,
                          plaintextLengthOut,
                          firstError,
                          sizeof(firstError)) ||
        DecryptCrypt5Body(body,
                          bodyLength,
                          privateKeyBase64,
                          attempts[1],
                          plaintextOut,
                          plaintextLengthOut,
                          secondError,
                          sizeof(secondError))) {
        success = 1;
    } else {
        SetError(errorOut,
                 errorCapacity,
                 "%s",
                 secondError[0] != '\0' ? secondError
                                         : (firstError[0] != '\0' ? firstError : "crypt5 decryption failed"));
    }

cleanup:
    if (shuffled) free(shuffled);
    return success ? 1 : -1;
}

int VCHappDecryptLink(const char *link,
                      unsigned char **plaintextOut,
                      size_t *plaintextLengthOut,
                      char *modeOut,
                      size_t modeCapacity,
                      char *errorOut,
                      size_t errorCapacity) {
    int result;
    if (plaintextOut) *plaintextOut = NULL;
    if (plaintextLengthOut) *plaintextLengthOut = 0;
    if (modeOut && modeCapacity > 0) modeOut[0] = '\0';
    if (errorOut && errorCapacity > 0) errorOut[0] = '\0';
    if (!VCHappIsEncryptedLink(link)) return 0;

    if (strncasecmp(link, kHappCrypt5Prefix, sizeof(kHappCrypt5Prefix) - 1) == 0) {
        if (modeOut && modeCapacity > 0) {
            snprintf(modeOut, modeCapacity, "%s", "crypt5");
            modeOut[modeCapacity - 1] = '\0';
        }
        return DecryptCrypt5Link(link,
                                 plaintextOut,
                                 plaintextLengthOut,
                                 errorOut,
                                 errorCapacity);
    }

    if (modeOut && modeCapacity > 0) {
        snprintf(modeOut, modeCapacity, "%s", "crypt4");
        modeOut[modeCapacity - 1] = '\0';
    }
    result = VCHappDecryptCrypt4Link(link,
                                     plaintextOut,
                                     plaintextLengthOut,
                                     errorOut,
                                     errorCapacity);
    return result;
}

void VCHappFreePlaintext(void *plaintext) {
    free(plaintext);
}
