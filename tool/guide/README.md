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
## P1-39 desktop/tablet overview capture

`assets/guide/desktop-overview.png` is a 1280 x 800 widget-rendered capture of
the shared Flutter overview, using the real local fixture repositories and
bundled Montserrat/Material icon fonts. It is not a Windows or iPad device pass.
Phone guide screenshots are unchanged because phone navigation is unchanged.
Regenerate the capture with:

```powershell
flutter test --no-pub --dart-define=CAPTURE_DESKTOP_GUIDE=true test/features/conferences/conference_dashboard_test.dart
```

The in-app guide now describes selecting a conference and searching its activities
on wide windows. Rebuild the deck and PDF from `content.js` after integrating the
parallel guide changes; the desktop capture has a landscape aspect ratio and
must not be squeezed into an existing phone frame.
