ZBAR_DIR := third_party/zbar/zbar
ZBAR_SRC := \
	$(ZBAR_DIR)/config.c \
	$(ZBAR_DIR)/decoder/qr_finder.c \
	$(ZBAR_DIR)/decoder.c \
	$(ZBAR_DIR)/error.c \
	$(ZBAR_DIR)/image.c \
	$(ZBAR_DIR)/img_scanner.c \
	$(ZBAR_DIR)/qrcode/bch15_5.c \
	$(ZBAR_DIR)/qrcode/binarize.c \
	$(ZBAR_DIR)/qrcode/isaac.c \
	$(ZBAR_DIR)/qrcode/qrdec.c \
	$(ZBAR_DIR)/qrcode/qrdectxt.c \
	$(ZBAR_DIR)/qrcode/rs.c \
	$(ZBAR_DIR)/qrcode/util.c \
	$(ZBAR_DIR)/refcnt.c \
	$(ZBAR_DIR)/scanner.c \
	$(ZBAR_DIR)/symbol.c
