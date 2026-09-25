# Save feedback

Explicit saves use SAVE → SAVING → SAVED with EXIT. SAVING is light green
(`#ABD4B8`); confirmed SAVED is dark green (`#2F6E46`). The spinner is CSS-only
and stops animating when reduced motion is requested.

B4 retains its reviewed `SaveActions` implementation. The other editors use
`useSaveFeedback`, `SaveScope`, and native control wrappers from
`src/components/save-feedback.tsx`. Each editor owns its own feedback state.
The wrappers preserve existing attributes and disable inputs, add/remove
controls, and cancellation during a request and while a receipt is displayed.

## Integration contract

- Use `SaveSubmit` for an explicit save and `SaveCancel` for cancellation.
- Call the transition function for the existing asynchronous operation.
- Handle validation failures as before, preserving the draft.
- Only after a successful server result, update the saved snapshot/revision and
  call `saveFeedback.complete(() => { ... })` with the existing editor-close,
  draft-reset and refresh work. That work runs once when EXIT is selected.
- If updating the snapshot would remove the active save control (B2's suggested
  default row), retain that update in the completion callback too.
- Keep helper components' controls inside the same scope. Use the shared input,
  select, textarea and button wrappers so they obey the editor's locked state.
- Automatic checkbox updates and removals do not require an extra EXIT.
  They keep their existing workflow. Do not mark a save successful from a timer.
- Unexpected request failures restore editing and display a retry message.
  The controller prevents duplicate requests while busy or awaiting EXIT.

## Current coverage

A2/B1 details, logo saves, classes, commodity codes, densities, B2, B3, B4,
B5/ULD inventory; C1, C2, C4, C7, C11; D2–D6, D8, D9, D11;
E1.1, E1.2, E2–E5; F1, G1 and H1.

C5 envelopes and C8 fuel tables retain their previous save behaviour pending
agreement on their high-volume entry workflow. No ADD ROW auto-save has been
introduced. Read-only, generated and unsupported pages have no new save controls.

## Verification

`tests/save-feedback.test.ts` covers server-confirmed receipts, duplicate request
prevention, validation failure, network failure/retry, EXIT, and automatic updates.
Live checks covered C4, B3 and D9 success/EXIT; E2's server validation failure
retained the draft without claiming success. F1 was checked visually in edit mode.
C5 envelope values were not saved during verification.
