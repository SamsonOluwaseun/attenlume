# Quick guide generator

One text, three outputs:

- `content.js`: the guide's text (UK English). Edit this, not the outputs.
- `build_dart.js` writes `lib/features/guide/guide_content.dart` (the in-app guide).
- `build_deck.js` writes the PowerPoint (Samlytics brand, PptxGenJS).
- `build_html.js` writes an A4 HTML page that Edge prints to PDF.

Screenshots are in `assets/guide/` (540 × 1200 JPEG), captured from an Android phone emulator with the conference "Samlytics Conference 2026". Use only Samlytics names in screenshots and examples.

## Rebuild

```powershell
cd tool\guide
npm install                      # once: pptxgenjs
node build_dart.js ..\..\lib\features\guide\guide_content.dart
dart format ..\..\lib\features\guide\guide_content.dart
node build_deck.js ..\..\docs\user-guide\Attenlume-Quick-Guide.pptx
node build_html.js guide.html
& "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" --headless=new --no-pdf-header-footer --allow-file-access-from-files --print-to-pdf="$PWD\..\..\docs\user-guide\Attenlume-Quick-Guide.pdf" "file:///$($PWD -replace '\\','/')/guide.html"
```

The deck uses Montserrat. Install it from `assets/fonts` to see it in PowerPoint; without it PowerPoint falls back to a similar font.
