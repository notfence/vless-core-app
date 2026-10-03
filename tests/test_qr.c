#include <zbar.h>
#include "check.h"
#include <stdint.h>
int main(void) {
    FILE *file = fopen("qr_fixture.txt", "r"); CHECK("qr/local-fixture-present", file != NULL);
    char matrix[128][130]; unsigned side = 0;
    while (side < 128 && fgets(matrix[side], sizeof(matrix[side]), file)) side++;
    fclose(file); CHECK("qr/square-fixture", side > 0 && strcspn(matrix[0], "\r\n") == side);
    unsigned scale = 8, width = side * scale; uint8_t *pixels = malloc(width * width); CHECK("qr/pixels-allocated", pixels != NULL);
    for (unsigned y = 0; y < width; y++) for (unsigned x = 0; x < width; x++) pixels[y * width + x] = matrix[y / scale][x / scale] == '1' ? 0 : 255;
    zbar_image_scanner_t *scanner = zbar_image_scanner_create(); zbar_image_t *image = zbar_image_create(); CHECK("qr/decoder-created", scanner && image);
    zbar_image_scanner_enable_cache(scanner, 0); zbar_image_set_format(image, zbar_fourcc('Y', '8', '0', '0'));
    zbar_image_set_size(image, width, width); zbar_image_set_data(image, pixels, width * width, zbar_image_free_data);
    CHECK("qr/real-decoder-found-symbol", zbar_scan_image(scanner, image) == 1);
    const zbar_symbol_t *symbol = zbar_image_first_symbol(image);
    CHECK("qr/decoded-uri", symbol && zbar_symbol_get_type(symbol) == ZBAR_QRCODE && !strcmp(zbar_symbol_get_data(symbol), "socks5://127.0.0.1:1080#vless-core"));
    zbar_image_destroy(image); zbar_image_scanner_destroy(scanner); FINISH("QR decoding"); return 0;
}
