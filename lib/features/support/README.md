# Voluntary support (P1-48)

Exports complete before this optional prompt. Payment is never required to
record, transcribe, export, copy or share. The first eligible successful export
may ask; **Maybe later** permits one neutral reminder. **Don't ask again** is
stored locally. Clicking Gift now is not proof of payment.

Disabled by default. At build time, configure a public receiving link and an
explicitly reviewed channel using Flutter `--dart-define`:

- `ATTENLUME_SUPPORT_URL`: public HTTPS PayPal.Me recipient link, hosted PayPal
  donate link or `/ncp/payment/` link. Never credentials, account-management links
  or bank details. The owner's public default is
  `https://www.paypal.com/donate/?hosted_button_id=EMQCVQHTPDR2U`.
- `ATTENLUME_SUPPORT_DISTRIBUTION=windows-direct` for direct Windows builds, or
  `android-direct` for reviewed, directly distributed APKs.

Missing/invalid values disable prompts and never block export. Store and iOS
builds remain disabled until their appropriate payment method and rules have
been reviewed. Do not mark a store build as direct to bypass that gate.

Amounts are suggested £5, £10, £20 and Other. PayPal.Me receives the selected GBP amount
path; other hosted links retain their configured checkout. Users confirm the
amount in PayPal. No payment SDK, receipt verification, unlock, subscription,
analytics or banking-data storage is included.

Windows opens the validated link in the system browser; Android uses a browsable
HTTPS intent. Tests inject fake openers and never open checkout or send money.
The supplied hosted Donate page publicly displays Samlytics Data Service and
the Attenlume support message. Actual receipt and final checkout choices still
need a manual check; no automated payment has been submitted.
Browser/provider failure leaves the completed export available.

P1-51: Settings > Support Attenlume remains available on eligible direct builds
even after automatic prompts are suppressed. User-initiated support never reads
or writes reminder preferences; manual copy has no export-ready claim. Browser
failures show a retry notice. README and public PDF/PPTX guide include the link.
