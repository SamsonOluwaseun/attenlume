# Button

Buttons for every action outside the recording controls, in four emphasis levels.

**Consumer provides:** `variant` (`primary`, `secondary`, `ghost`, `danger`), `label` (sentence case, a verb), optional leading icon, `onPress`, `disabled` with a reason shown nearby.

**Variants**

- `primary`: `brand` fill with a cream `on-brand-large` label, as in the supplied screens ("Get started", "Export conference"). Label 19px Semibold so cream on blue meets the large-text rule. One per screen, full width on phones.
- `secondary`: transparent with a 1.5px `line-strong` border and `ink` label. On navy screens (splash) the border and label are cream.
- `ghost`: text only in `ink`, underlined on hover, for low-emphasis actions like "Skip for now".
- `danger`: `danger` fill, `on-danger` label. Only for destructive actions, always behind a confirmation that names what will be deleted.

**Rules**

- Height at least 52px for primary and secondary, radius `radius-md`, padding `space-3` by `space-5`.
- Never cream text on blue below 19px Semibold (3.15:1). Small buttons on blue use `on-brand` (navy).
- Focus ring: 2px `focus`, 2px offset.
