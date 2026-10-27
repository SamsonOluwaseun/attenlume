# Attenlume by Samlytics: Design Guide

**Version:** 1.3, 27 October 2026 (owner-supplied logo artwork adopted as is, typography and screens aligned to the supplied boards, navy recording screen confirmed)
**Say it:** a-TEN-loom
**Tagline:** Be present. Bring ideas to light.
**Source of truth:** this file and `design/tokens.json`. The same system lives as a browsable Claude design system for people. If they ever disagree, this file wins in the repo.
**Brand source:** Samlytics Data Services Brand Guidelines (palette, Montserrat, slanted-band motif, voice).

## For coding agents

- The product name is **Attenlume** everywhere: app display name, store listing, About screen. Suggested identifiers: iOS bundle `com.samlytics.attenlume`, Android package `com.samlytics.attenlume`, deep-link scheme `attenlume://`. Confirm with the owner before first store submission.
- **The recording screen is navy (`live-surface`) in both light and dark themes.** The owner confirmed this on 27 October 2026. Lime (`live`) only shows live recording status. The Stop control uses the `stop` red square, as in the supplied screen. `danger` is only for destructive actions and critical storage.
- **The logo is supplied artwork. Use `assets/brand/logos/` exactly as supplied.** Never redraw, trace, re-proportion or retype it. The long cream stroke of the A is intentional. Never sample UI colours from the logo images: the artwork's blue is brighter than the `brand` token.
- **Screens:** build to `assets/brand/reference/attenlume-screens-board.png` for layout and content, using tokens and component specs for every value. The free app has no sign-in (NFR-01): the splash screen's "Sign in" button only appears once optional cloud export exists (Phase 1.5).
- Build the Flutter `ThemeData` from `design/tokens.json`. Do not hard-code hex values in widgets. Create `lib/app/theme/tokens.dart` (generated constants) and `lib/app/theme/app_theme.dart` (light and dark `ThemeData`, plus a `LiveTheme` for the recording screen).
- Bundle Montserrat (SIL Open Font License) from `assets/fonts/`: Regular 400, Medium 500, Semibold 600, Bold 700. Declare them in `pubspec.yaml`.
- Bundle `attenlume-logo-horizontal.png` and `attenlume-logo-stacked.png` as image assets for the splash and About screens. Generate platform app icons from `attenlume-app-icon-primary.png` with `flutter_launcher_icons` (iOS full-bleed without transparency, Android adaptive with a navy background, Windows .ico), without altering the artwork.
- Every text and fill pair has to meet the contrast rules in each token's usage. Add a widget test that checks the main pairs (NFR-09).
- Icon set: Lucide (ISC licence) via a maintained Flutter package. Confirm licence and maintenance in P0-08.
- Siri and assistant phrases use the name: "Start session in Attenlume". Test recognition early in spike P0-13.

### Flutter mapping

| Token | Flutter |
|---|---|
| `surface` | `ColorScheme.surface`, `scaffoldBackgroundColor` |
| `surface-raised` | `ColorScheme.surfaceContainer`, `CardTheme.color` |
| `ink` / `ink-muted` | `ColorScheme.onSurface` / `onSurfaceVariant` |
| `brand` / `on-brand-large` | `ColorScheme.primary` / `onPrimary` = cream, with `FilledButton` labels at 19px Semibold. Small text on blue uses `on-brand` (navy) |
| `brand-tint` | `ColorScheme.primaryContainer`, `onPrimaryContainer` = `ink` |
| `danger` / `on-danger` | `ColorScheme.error` / `onError` |
| `line` / `line-strong` | `outlineVariant` / `outline` |
| `live`, `live-surface`, `live-raised`, `on-live*`, `stop`, `success`, `warning-fill`, `on-brand-large` | a `ThemeExtension<AttenlumeColors>` |
| type styles | `TextTheme`: `display`→displaySmall, `title`→headlineSmall, `heading`→titleLarge, `body`→bodyLarge, `body-small`→bodyMedium, `label`→labelLarge, `caption`→labelSmall, `timer` and `stat` in the extension |
| `radius-md` | `FilledButtonTheme`, `CardTheme`, `InputDecorationTheme` shapes |
| `tap-min` | `MaterialTapTargetSize.padded`, minimum button size 48 |

Set `ThemeMode.system` for the app and force the live theme on the recording screen in both modes.

---

## Brand and usage rules

Attenlume is the conference capture app from Samlytics Data Services. It lets an attendee set their goals, record sessions, snap slides and tap bookmarks, then put the phone away and listen. This system applies the Samlytics brand (blue, navy, cream, lime, Montserrat, rounded tiles, pills) to a calm, pocket-first mobile and Surface app. The logo, brand board and screen designs supplied by the owner are the reference for everything below.

### Name and meaning

- Write the product name as **Attenlume**, one word, capital A only. Never "AttenLume", "Atten Lume" or "ATTENLUME" in running text. In first use on store listings, splash and About screens write **Attenlume by Samlytics Data Services**. Inside the app, "Attenlume" alone is enough.
- Say it **a-TEN-loom**: "atten" as in attention, "lume" to rhyme with room. Put the pronunciation in launch posts, the store description and the About screen.
- Where it comes from: **Atten**, from attention and attend, is being fully present. **Lume**, from the Latin *lumen*, meaning light, is understanding and insight.
- What it means: **it represents being fully present at events and illuminating ideas through captured knowledge.** You give the speaker your attention, Attenlume holds on to what matters, and afterwards the ideas come to light in your notes, your takeaways and your work.
- Tagline: **Be present. Bring ideas to light.** Supporting line: **Take the knowledge home.**

#### Ready-to-use copy

Use these as written so the meaning is told the same way everywhere.

- **One line (store subtitle, social bio):** "Be present at every session. Capture what matters. Bring ideas to light."
- **Short description:** "Attenlume records sessions, links your slide photos to the moment they were shown and bookmarks key points, so you can listen instead of typing notes. Afterwards, take home an organised package for your own notes or your AI tool."
- **The name, for the About screen and launch posts:** "Attenlume (a-TEN-loom) is a combination of Atten, from attention and attend, and Lume, from the Latin lumen, meaning light. It represents being fully present at events and illuminating ideas through captured knowledge."
- **Onboarding card:** "Give the speaker your attention. Attenlume will hold on to the details."
- **Spoken (podcast, demo, event stage):** "It's called Attenlume. Atten, as in attention. Lume, as in light."
- **Why we built it:** "At conferences we kept missing the talk while trying to capture it. Attenlume lets you stay in the moment and still leave with everything you need."

### Key features (store listing and website)

Use these six, in this order, with these words.

- **Record:** capture audio, slides and ideas.
- **Photograph:** capture slides, whiteboards and moments.
- **Organise:** keep everything by conference and session.
- **Export:** download or export to Google Drive or OneDrive.
- **Gain insights:** turn sessions into searchable notes, with AI as an option.
- **Be present:** focus on the moment while Attenlume captures knowledge.

#### How the meaning shows up in the brand

- **The wordmark** sets "Atten" in navy and "lume" in blue. It shows the meaning and where the word splits, which helps people say it.
- **The mark is an A made of attention and light.** The long cream stroke is *atten*. The lime light and its beam are *lume*, like a spotlight on the speaker and the moment an idea comes to light.
- **The recording screen** is navy, "house lights down", so the only light on screen is the lime of a live recording.
- In copy, use light naturally and sparingly ("bring ideas to light", "see it clearly"). Avoid puns on "illuminate" or "enlighten" in every message.

### Voice and copy

Samlytics' voice is knowledgeable and reassuring, its tone friendly yet professional. In Attenlume that means a calm assistant that never makes the user feel they have lost something.

- UK English. Sentence case everywhere, including buttons ("Get started", "Export conference", not "Export Conference").
- Address the user as "you". The app does not say "I" or "we" in status messages.
- Say what happened, then what to do. One idea per sentence. No exclamation marks, no emoji.
- Never blame the user. Never say "Oops".
- Numbers: "47 min", "3 h 12 min", "About 45 minutes of space left".

Real copy to reuse:

- "Recording paused for a call. It will carry on when you hang up."
- "Couldn't resume after the call. Tap to carry on recording."
- "'Data mesh in practice' is still recording. Stop it and start a new one?"
- "About 45 minutes of space left at Balanced quality."
- "Storage nearly full. Recording stopped and saved."
- "Some events and speakers don't allow recording. Record only when permitted."
- Empty conference: "Nothing captured yet. Start your first activity when the session begins."

### Logo

The logo is supplied artwork. Use it exactly as supplied: the files in the Logos and App-icons groups are the masters.

**What the mark shows.** A letter A on a rounded square tile. The cream stroke rises from the bottom left and, by design, runs longer than a usual A: it carries on over the top and curls down on the right like a lamp hood, sheltering the lime light beneath it. From that light a lime beam widens down to the base of the tile. The long stroke is attention leaning in. The light and beam are the idea coming to light. The longer leg is intentional and is part of the design.

- **Never redraw, trace, re-proportion or "correct" the mark.** Do not shorten the long stroke, close the A, move the light, recolour, stretch, rotate, outline, or add shadows, glows or gradients.
- **Never retype the wordmark** in a font. "Atten" is navy and "lume" is blue in the supplied artwork. Use the image.
- `attenlume-logo-horizontal.png`: blue tile, "Attenlume" and "by Samlytics Data Services" to the right. Use for app headers on wide screens, documents, slides, email signatures and the website.
- `attenlume-logo-stacked.png`: blue tile above the wordmark. Use for splash screens, posters, social avatars with room for text and square spaces.
- `attenlume-app-icon-primary.png`: navy tile with cream A and lime light. The primary app icon and the mark on its own.
- The brand board also shows the icon on a cream (light background) tile and a blue tile. Use those only once they are supplied as files.
- Both lockups have transparent backgrounds. Place them on `surface` (cream) or white. On navy or photographs use the stacked lockup only where the tile and the navy wordmark stay readable, otherwise use the app icon mark alone.
- Clear space: at least the diameter of the lime light on every side. Minimum size: mark 24px on screen, horizontal lockup 140px wide.
- The parent Samlytics logo appears only on the About screen and store listings.

**Production notes (artwork stays as it is):**

- The supplied files are high-resolution PNGs, fine for screens and documents. For print, store assets and crisp scaling, ask the designer for **SVG (vector) masters of the same artwork**.
- The blue in the logo artwork measures about **#1E85FB**, brighter than the Samlytics UI blue (#4392F1). Keep the logo as supplied. UI uses the `brand` token, never colours sampled from the logo.
- App stores need exports made from the same artwork: **iOS 1024 × 1024 with no transparency and no rounded corners** (iOS applies its own mask, and App Store Connect rejects icons with transparency), **Android adaptive** foreground and navy background layers plus a monochrome layer, and a **Windows .ico** at 16 to 256px.

### Colour

Use semantic tokens in UI, never the palette tokens directly. The official values are the Samlytics palette: blue #4392F1, navy #00212B, cream #FEFFF8, lime #DCFF38, deep lime #C2E812. (One of the supplied boards lists slightly different hex values. The Samlytics values above are correct.)

- Light theme: `ink` on `surface`, cards on `surface-raised`. Dark theme follows the device setting and swaps the same tokens.
- **The recording screen is always `live-surface` (navy), in both themes.** Dim screen in a dark hall, less battery on OLED, and lime only ever appears on navy, where it reads 14.7:1. Lime is used only to show live recording status.
- `brand` (blue) is for fills, selected states, progress, icons and display text at 24px or larger. It is 3.15:1 on cream, so never use it for body or small text.
- Primary buttons are blue with cream labels (`on-brand-large`), as in the supplied screens. Set those labels at 19px Semibold or larger so they meet the large-text contrast rule. Smaller labels on blue use `on-brand` (navy, 5.3:1).
- `live` (lime) means one thing: recording is on. Do not use it for decoration inside the app. It is never placed on cream (1.1:1).
- `stop` (red) is only the square inside the Stop control on the recording screen.
- `success` (deep lime) is a fill with `on-success` navy text and always a word or tick: "Saved", "Exported", "Verified".
- `danger` is for destructive actions and critical storage, with an icon and a sentence. `stop` and `danger` are functional colours outside the Samlytics palette.
- `warning-fill` for low storage and battery banners, always with an icon and text.
- Colour never carries meaning alone. Recording state always shows the word ("LIVE", "Paused") and the timer.

### Typography

Montserrat throughout, as on the supplied brand board.

- **Headings: Montserrat Bold.** `display` for the conference name on its home screen, `title` for screen titles.
- **Subheadings: Montserrat Semibold.** `heading` for activity titles and section headings. `label` for buttons, tabs and navigation.
- **Body text: Montserrat Regular.** `body` (16px) is the default. `body-small` for metadata lines.
- **Captions: Montserrat Medium.** `caption` for labels under icons and technical details.
- `timer` uses tabular figures (`font-feature-settings: "tnum"`) so the digits do not shuffle.
- Support the device's text size settings. Layouts must hold at 200% text.

### Screens and navigation

The supplied screens set the structure. Build to them.

- **Splash and onboarding:** navy screen with a conference photo, the logo, the tagline and a page indicator. Primary button "Get started". The supplied design also shows "Sign in": the free app needs no account (NFR-01), so this button appears only once optional cloud export exists (Phase 1.5), opens provider connection, and the app stays fully usable without it.
- **Bottom navigation (phones):** Conferences, Record, Library, Settings.
- **My conferences:** search field, add button, cards with a photo thumbnail, name, place and dates.
- **Recording session:** navy screen. Activity title and room at the top, a lime dot with "LIVE", the large timer, a lime level waveform, a Pause button and a Stop button (red square in a ring), then Photo, Bookmark and Note along the bottom.
- **Session review:** header photo, title, place, date and duration, tabs for Highlights, Timeline and Photos, and a Key moments list of bookmarks with their timestamps.
- **Export to cloud:** Google Drive, Microsoft OneDrive and Local files, an export format choice (for example "Audio + notes + photos") and a primary "Export conference" button.
- **Desktop and tablet (Windows):** a left sidebar with Home, Conferences, Sessions, Notes, Exports and Settings, a conference summary row (sessions, photos, notes, total size) and the sessions list.

### Shape and layout

- Radii follow the logo tile: `radius-md` for cards and buttons, `radius-lg` for hero panels, `radius-pill` for chips, status pills and the record controls.
- Phone gutter `space-4`, section gap `space-5`. Surface and tablets: content max 720px wide in the main column, gutters `space-5`.
- Every touch target is at least `tap-min` (48px). The record controls are `record-button` (96px).
- Thumb zone: on phones, primary actions sit in the bottom half of the screen.
- Flat by default. Separate layers with `surface-raised` and `line`. `shadow-sheet` only on bottom sheets.

### Iconography

- The supplied screens use rounded line icons. Attenlume uses **Lucide** (ISC licence) at `icon-md` (24px), 2px stroke, round caps. Flagged: confirm with the brand owner before release.
- Icons sit in `ink`, or `brand` for highlighted feature icons on light screens, or `on-live-surface` on the recording screen.
- Core icons: mic or video (record), camera, folder, cloud, lightbulb (insights), people (be present), bookmark, pause, square (stop), note, phone-off (interrupted), bluetooth.
- Every icon-only button has an accessible label.

### Imagery

Event photography (stages, speakers, audiences) is used on the splash screen, conference cards and marketing. Inside a conference, the photos are the user's own. Never ship real people's photos in the app without permission.

### Motion

- Calm and short: 150 to 250 ms, ease-out. Nothing bounces.
- The live dot pulses gently (opacity 1 to 0.4, 1.6 s) while recording, and the waveform moves with the input level. Both stop when paused.
- Respect the OS "reduce motion" setting: no pulse, a static level bar, instant transitions.

### States

- Focus: 2px `focus` ring with 2px offset on every focusable element.
- Pressed: fill darkens by overlaying 12% navy. Disabled: 40% opacity plus a reason nearby where possible.
- Recording states always show words: LIVE, Paused, Interrupted, Saved.

### Accessibility

- Text pairs meet 4.5:1 in both themes (see each token's usage note), or 3:1 for large text. Control borders, focus rings and icons meet 3:1.
- Full VoiceOver, TalkBack and Narrator labels. The record controls announce their state and elapsed time.
- Haptic tick on record start, stop and bookmark, so the user can act without looking.

### App icon

The app icon is `attenlume-app-icon-primary.png`: the navy tile with the cream A and lime light, used as supplied. Store and platform exports are made from this same artwork (see Production notes under Logo).

---

## Token reference

### Colour

| Token | Light | Dark | Usage |
|---|---|---|---|
| `palette-blue` | #4392F1 | #4392F1 | Samlytics primary blue for all UI. The supplied logo artwork renders its blue brighter (about #1E85FB): leave the logo as supplied, but never sample UI colours from the logo image. |
| `palette-navy` | #00212B | #00212B | Samlytics primary navy (the brand's 'black'). Reference only. |
| `palette-cream` | #FEFFF8 | #FEFFF8 | Samlytics primary cream. Reference only. |
| `palette-lime` | #DCFF38 | #DCFF38 | Samlytics secondary lime. Reference only. |
| `palette-lime-deep` | #C2E812 | #C2E812 | Samlytics secondary deep lime. Reference only. |
| `surface` | #FEFFF8 | #00212B | Page background for every screen except the recording screen. |
| `surface-raised` | #EEF5FE | #0E3542 | Cards, sheets and list rows on surface. A tint of the brand blue in light, a lift of navy in dark. |
| `surface-brand` | #4392F1 | #4392F1 | Large brand fields: onboarding panels, empty states, the export success screen. Text on it is on-brand. |
| `live-surface` | #00212B | #00212B | The recording screen in BOTH themes ('house lights down'). Text on it is on-live-surface. |
| `live-raised` | #0E3542 | #0E3542 | Buttons and dividers on live-surface: the Pause button, the Photo, Bookmark and Note buttons (cream on it 13.0:1). |
| `ink` | #00212B | #FEFFF8 | Body copy and headings on surface and surface-raised (16.7:1 light, 16.7:1 and 13.0:1 dark). |
| `ink-muted` | #566C73 | #9FB3B8 | Secondary text, timestamps, helper text on surface and surface-raised (light 5.5:1 and 5.0:1, dark 7.7:1 and 6.0:1). Never on brand-tint (fails): use ink there. |
| `on-live-surface` | #FEFFF8 | #FEFFF8 | Text and icons on live-surface (16.7:1). |
| `on-live-surface-muted` | #9FB3B8 | #9FB3B8 | Secondary text on live-surface: storage estimate, input route (7.7:1). |
| `brand` | #4392F1 | #4392F1 | Primary button fill, selected states, progress fills, large display words (24px+), icons. NEVER body text on cream: 3.15:1. |
| `on-brand` | #00212B | #00212B | Labels and icons on brand fills below 19px Bold (5.3:1). For primary buttons use on-brand-large. |
| `on-brand-large` | #FEFFF8 | #FEFFF8 | Cream labels on brand fills, as in the supplied screens ('Get started', 'Export conference'). Only at 19px Bold or larger, where 3.15:1 meets the large-text rule. |
| `brand-tint` | #A1C8F8 | #1F4F6B | Selected chip fill, active list row. Text on it is ink. |
| `link` | #00212B | #7DB5F7 | Inline links, always underlined. Light uses navy because brand blue fails on cream at text size. |
| `live` | #DCFF38 | #DCFF38 | Recording is ON: the live dot, the record ring, the timer accent. Only ever on live-surface or navy (14.7:1). Never on cream (1.1:1). |
| `on-live` | #00212B | #00212B | Text and icons on a live (lime) fill (14.7:1). |
| `stop` | #EF4444 | #EF4444 | The red square of the Stop control on live-surface only, as in the supplied recording screen (4.5:1 on navy). Never for anything else. Not a Samlytics palette colour: functional exception. |
| `success` | #C2E812 | #C2E812 | Saved, exported and verified badges as a FILL with on-success text. Always paired with a word or a tick. |
| `on-success` | #00212B | #00212B | Text on success fills (11.9:1). |
| `danger` | #C42B36 | #FF8A85 | Delete, storage critical, errors. Functional colour outside the Samlytics palette (5.6:1 light, 7.4:1 dark). The Stop control uses stop, not danger. |
| `on-danger` | #FEFFF8 | #00212B | Text on a danger fill. |
| `warning-fill` | #FFF4C2 | #3A3A12 | Low-storage and low-battery banners. Text on it is ink. Always with an icon and a sentence. |
| `line` | #DCE3E0 | #1F4350 | Decorative dividers between list rows. Never the only boundary of a control. |
| `line-strong` | #7A8D93 | #6A8790 | Borders of inputs, outlined buttons and toggles (3:1 or more on surface). |
| `focus` | #4392F1 | #4392F1 | 2px focus ring with 2px offset on every focusable element (3.15:1 on cream, 5.3:1 on navy). |

### Type (Montserrat)

| Style | Size / line height | Weight | Usage |
|---|---|---|---|
| `display` | 40px / 44px | 700 | Conference name on its home screen. Montserrat Bold (brand board: headings). One per screen. |
| `title` | 28px / 34px | 700 | Screen titles: 'My conferences', 'Session review', 'Export to cloud'. Montserrat Bold. |
| `heading` | 20px / 26px | 600 | Subheadings and activity titles. Montserrat Semibold (brand board: subheadings). |
| `body` | 16px / 24px | 400 | Default text. Montserrat Regular (brand board: body text). |
| `body-small` | 14px / 20px | 400 | Metadata lines in cards: place, dates, duration. Montserrat Regular. |
| `label` | 15px / 20px | 600 | Buttons, chips, tabs, bottom navigation. Montserrat Semibold. Primary buttons with cream text go up to 19px. |
| `caption` | 12px / 16px | 500 | Small labels under icons ('Photo', 'Bookmark', 'Note') and technical details. Montserrat Medium (brand board: captions). |
| `timer` | 56px / 60px | 700 | Elapsed time on the recording screen. Use tabular figures so digits do not jump. |
| `stat` | 24px / 28px | 700 | Totals on conference home and Storage Manager. |

### Spacing, radius and size

| Token | Value | Usage |
|---|---|---|
| `space-1` | 4px | Icon to label gap inside chips. |
| `space-2` | 8px | Gap between chips, between a title and its metadata. |
| `space-3` | 12px | Inner padding of chips and small buttons. |
| `space-4` | 16px | Screen side gutter on phones, card padding. |
| `space-5` | 24px | Gap between sections, card padding on tablets and Surface. |
| `space-6` | 32px | Gap above a screen title, around the record button. |
| `space-7` | 48px | Large breathing room on onboarding and empty states. |
| `radius-sm` | 8px | Inputs, small thumbnails. |
| `radius-md` | 16px | Cards, sheets, buttons. |
| `radius-lg` | 24px | Large panels and hero tiles, echoing the logo tile. |
| `radius-pill` | 999px | Chips, status pills, the record ring. The brand's pill motif. |
| `tap-min` | 48px | Minimum touch target on every control. |
| `record-button` | 96px | Diameter of the record button. |
| `icon-md` | 24px | Default icon size, 2px stroke. |

## Components

Specs for RecordButton, Button, ActivityCard, BookmarkChip, StorageMeter and StatusPill are in `docs/design/components/<Name>.md`.

## Logo and icon files

See `assets/brand/README.md`: the supplied logo artwork, the reference boards and the platform exports still to be made from the artwork.
