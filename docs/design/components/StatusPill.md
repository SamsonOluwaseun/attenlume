# StatusPill

A short word that states an activity's recording or export state, so state never relies on colour.

**Consumer provides:** `status` (`recording`, `paused`, `interrupted`, `saved`, `exported`, `verified`, `private`).

**Mapping**

- recording: `live` fill, `on-live` text, pulsing dot. Only on navy surfaces. On cream it becomes a navy pill with a lime dot and cream text.
- paused, interrupted: transparent with `line-strong` outline, `ink` text, pause or phone-off icon.
- saved, exported, verified: `success` fill, `on-success` text with a tick. "Verified" only after checksums pass (FR-EXP-06).
- private: `line-strong` outline, lock icon.

Text style: 12px Bold in sentence case, padding 4px by 10px, `radius-pill`.
