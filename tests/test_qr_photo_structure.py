from pathlib import Path

root = Path(__file__).resolve().parents[1]
scanner = (root / "app/qr_scanner.m").read_text()
imports = (root / "app/main_import.m").read_text()
assert "photoPressed" in scanner, "photo/button-missing"
assert "UIImagePickerControllerSourceTypePhotoLibrary" in scanner
assert "qrScanVC:(UIViewController *)vc didScanTexts:" in imports
assert "NSPhotoLibraryUsageDescription" in (root / "app/Info.plist").read_text()
opening = imports.split("- (void)startQRImportFlow", 1)[1].split("\n}", 1)[0]
assert "UIImagePickerControllerSourceTypeCamera" not in opening
source = (root / "app/qr_photo_source.m").read_text()
assert "UIImagePickerControllerOriginalImage" not in scanner
assert "CGImageSourceCreateThumbnailAtIndex" in source
assert "CGImageSourceCreateImageAtIndex" not in source
assert "-framework ImageIO -framework AssetsLibrary" in (root / "Makefile").read_text()
print("photo QR structure: passed")
