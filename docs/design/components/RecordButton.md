# RecordButton

The recording controls on the navy recording screen, as in the supplied design: Pause and Stop side by side, with Photo, Bookmark and Note below.

**Consumer provides:** `state` (`idle`, `recording`, `paused`, `interrupted`), `elapsed` (seconds), `onRecord`, `onPause`, `onStop`, `onPhoto`, `onBookmark`, `onNote`, and accessible labels that include the activity title.

**Anatomy (top to bottom):**

- Status: a lime `live` dot and the word "LIVE" in lime while recording. "Paused" in `on-live-surface-muted` when paused.
- Timer in the `timer` style, cream (`on-live-surface`).
- Level waveform in `live` (lime), drawn from input level, paused with the recording.
- **Pause / Resume:** a `record-button` (96px) circle filled `live-raised`, with a cream pause glyph. Label "Pause" (or "Resume") under it in `caption`.
- **Stop:** a 96px circle with a 2px `on-live-surface-muted` ring and a `stop` red square inside. Label "Stop".
- **Idle (before recording):** a single 96px `brand` circle with a cream filled dot, label "Record".
- **Secondary row:** Photo (camera), Bookmark, Note, each a 56px icon button in cream with a `caption` label, on `live-raised`, separated by thin `live-raised` dividers.

**Rules**

- Lives only on `live-surface`.
- Pause and Stop are separate, so a stray tap never ends a session. Stop asks nothing but shows a toast "Saved" with an Undo for 5 seconds.
- Debounce taps (FR-REC-09): a second tap within 600 ms is ignored.
- Haptic tick on every change. The live dot pulses while recording, unless reduce motion is on.
- Screen reader labels: "Pause recording, Product innovation live, 28 minutes", "Stop and save recording".
