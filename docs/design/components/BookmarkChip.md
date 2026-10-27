# BookmarkChip

One-tap labels that mark a moment in the recording without typing.

**Consumer provides:** `label` (Important moment, Question, Follow-up, Key slide, Quote, or custom), `selected`, `onPress`.

**Rules**

- Pill shape (`radius-pill`), height `tap-min`, text style `label`.
- On the recording screen (navy): unselected is a 1.5px `on-live-surface-muted` outline with cream text. A tap sets the bookmark at once and flashes the chip `live` with `on-live` text for 600 ms, plus a haptic tick. The chip row scrolls sideways.
- On light screens (review, edit): unselected is a `line-strong` outline with `ink` text, selected is `brand-tint` fill with `ink` text. Never `ink-muted` on `brand-tint` (fails contrast).
- Tapping a chip never stops or pauses the recording.
