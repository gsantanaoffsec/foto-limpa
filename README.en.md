# Foto Limpa

[Português](README.md) · **English**

A native macOS application that exports copies of photos without the original file's embedded metadata and compares the data **before and after** processing. Image processing takes place on your Mac.

> A privacy and metadata inspection tool. It does not guarantee avoiding AI labels on social platforms, does not detect or remove invisible pixel watermarks such as SynthID, and does not certify that a photo is authentic.

## Purpose and practical uses

Photos may contain GPS coordinates, camera information, comments, and editing records that are not visible in the picture. Foto Limpa helps you create a copy for sharing, review which data changed, and keep the original file.

- Remove location and other embedded metadata before sharing photos.
- Strip camera, editing, comment, and provenance records from the exported file.
- Inspect differences between the original and the processed copy.
- Convert supported photos to JPEG or PNG.
- Process images without an account or uploading photos to a server.

## Features

- Single-frame JPEG, PNG, HEIC, or TIFF input; JPEG (95% quality) or PNG output.
- Reconstructs the image without copying the original EXIF, GPS, IPTC, XMP, or embedded C2PA data.
- Structural inspection of JPEG segments, PNG chunks, and data after the image end marker.
- Comparison with previews, fields, values, file size, and SHA-256; removed, changed, added, and unchanged states.
- Field/value search and a changes-only filter.
- JSON report with the original inspection, output inspection, and differences.
- 1–5 decoding, export, and verification passes; one pass is recommended.
- Optional random neutral filenames for the copy.
- Checks saved bytes and metadata covered by the inspection after writing the file.
- Prevents overwriting the original, including equivalent paths and symbolic links.

The current application interface is in Portuguese; documentation is available in both languages.

## Technologies

| Technology | Role in this project |
| --- | --- |
| Swift | Application and test implementation. |
| SwiftUI | Interface, view state, tabs, filters, and comparison. |
| AppKit | File selection/saving, preview images, and Finder integration. |
| ImageIO | Image decoding, orientation, metadata reading, and JPEG/PNG encoding. |
| CoreGraphics | Rendering a fresh sRGB bitmap. |
| UniformTypeIdentifiers | File format identification in file dialogs. |
| CryptoKit | SHA-256 calculation for inspection and comparison. |
| Foundation and Grand Central Dispatch | File operations, JSON, and background processing. |
| Bash, `xcrun swiftc`, and `codesign` | Testing, compilation, and local ad hoc signing. |

Uses system frameworks with no third-party runtime dependencies.

## Requirements

- An **Apple Silicon** Mac (arm64: M1 or later).
- **macOS 13 or later** as the deployment target.
- To build: Apple developer tools with `swiftc`, the macOS SDK, and `codesign` available through `xcrun`.

Compilation and tests have been checked in the available development environment; not every earlier macOS version has been validated. The current script produces arm64 binaries only.

## Download and use

1. Open [Releases](https://github.com/gsantanaoffsec/foto-limpa/releases) and download the ZIP for the desired version.
2. Extract it and open `Foto Limpa.app`. Optionally move it to Applications.
3. Click **Selecionar foto…** (Select photo) and choose a supported file.
4. Choose JPEG or PNG and the number of passes. Start with **1 · recomendada** (recommended).
5. Click **Limpar e comparar** (Clean and compare).
6. Review the previews and metadata in **Antes × depois** (Before/after). Use **Só alterações** (Changes only) and the search box to filter the table.
7. Click **Salvar cópia…** (Save copy) to choose an output location.
8. Optionally use **Salvar relatório…** (Save report) to export the comparison as JSON.

**The report includes original values, including GPS coordinates if present.** Keep it separate from any image you plan to share.

The app uses a **local ad hoc signature**, without an Apple Developer ID certificate or notarization. If macOS blocks it, check the options for this specific application under **System Settings → Privacy & Security**. You do not need to disable system-wide security protections.

Processing is local. Selecting the Help item about AI labels opens an external page in your browser.

## Build from source

```bash
git clone https://github.com/gsantanaoffsec/foto-limpa.git
cd foto-limpa
bash build.sh
```

The script builds and signs `dist/Foto Limpa.app`. To open it:

```bash
open "dist/Foto Limpa.app"
```

If Apple developer tools are not installed yet, request installation with `xcode-select --install` and complete the installer before building.

## Run tests

```bash
bash test.sh
```

Tests generate synthetic images locally and cover EXIF/GPS/IPTC removal, orientation, dimensions, PNG transparency, rejection of invalid files and multiple frames, keeping the original unchanged, symbolic-link protection, comparison, SHA-256, and JSON reports. They also check three JPEG passes, five PNG passes, invalid pass counts, APP11 blocks, PNG text, caBX, and data after a JPEG end marker.

Synthetic C2PA blocks test structural inspection and removal, **not** signature validation. No test publishes images to social networks.

## How it works

1. Checks file size, dimensions, and frame count.
2. Decodes the image with orientation applied.
3. Draws the pixels into a fresh 8-bit sRGB bitmap.
4. Encodes a new JPEG/PNG without copying the original properties.
5. Discards additional blocks while retaining the permitted image structure and color information.
6. Inspects the result; additional passes use the output as the next input.
7. When saving, reads and verifies the file written to disk.

Dimensions and necessary technical information, such as a generic color profile, may remain. The removed-field count is not a count of removed AI signals: it also includes technical properties and multiple representations of the same data.

## Limitations

- Maximum **100 megapixels** and **250,000,000 bytes** per file.
- Animations and multi-image files are rejected. Some HEIC files containing auxiliary images may need to be exported as a still photo first.
- Structural inspection of the input covers JPEG/PNG. For HEIC/TIFF, property and XMP inspection is **partial**, as stated in the interface.
- Output is **sRGB, 8-bit, and SDR**: HDR, higher bit depths, and colors outside sRGB may look different.
- JPEG recompresses the image and renders transparency against a white background. PNG preserves transparency and uses lossless encoding **after** bitmap conversion.
- Additional passes may accumulate JPEG quality loss without an extra guarantee against AI detection.
- A different SHA-256 shows that bytes changed, without proving the image became unrecognizable.
- Does not detect/remove pixel watermarks, erase external provenance records, or modify existing social media posts.
- APP11/JUMBF is treated as possible C2PA provenance; signatures are not validated. The app does not create capture credentials or prove authenticity.
- Does not encrypt photos: an encrypted file cannot be published directly as a regular image.

## Structure

```text
.
├── README.md                   # Portuguese documentation
├── README.en.md                # English documentation
├── Info.plist                  # macOS application metadata
├── Sources/
│   ├── App.swift               # Interface and user flow
│   ├── Cleaner.swift           # Decoding, cleaning, encoding, and saving
│   └── MetadataAudit.swift     # Inspection, comparison, SHA-256, and reporting
├── Tests/
│   └── main.swift              # Tests using synthetic images
├── build.sh                    # Builds the Apple Silicon .app
└── test.sh                     # Compiles and runs tests
```

Generated `.build/` and `dist/` directories are not tracked in Git.
