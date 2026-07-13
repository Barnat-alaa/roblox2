# Asset license registry

## Current status

As of 2026-07-13, no external Roblox asset IDs or imported production meshes, textures, images, animations, fonts, music, or sound effects are registered for shipment. Repository search found no project asset-content IDs outside generated tool metadata. The current code/Studio greybox uses project-authored primitives and configuration.

This is not approval to import arbitrary Creator Store assets later. Every non-code asset must be registered before Staging or publication.

## Rules

- Accept only project-original work, commissioned work with written commercial rights, or third-party work whose license clearly permits the intended Roblox/commercial use.
- Keep editable source, export, creator, source URL, license/version, proof, modifications, Roblox asset ID, and approval status.
- Do not rely on “found online,” search-result previews, attribution alone, or an asset being visible in the Creator Store as proof of rights.
- Do not use assets extracted from another game, traced screenshots, unofficial rips, copyrighted reference imagery as final material, or content that implies affiliation with Wild Ones.
- Verify trademark, personality/publicity, privacy, and music-performance/sample rights separately where applicable.
- License review is asset-specific; one approved item does not approve the creator’s entire library.
- If proof is missing, ambiguous, expired, or incompatible, status is BLOCKED and the asset is excluded from every published build.

## Status codes

| Status | Meaning |
| --- | --- |
| PROTOTYPE_ONLY | project-original primitive/temporary work; not marketing/production approved |
| PENDING | source/evidence collected but review incomplete |
| APPROVED_PRIVATE | cleared only for private test scope |
| APPROVED_PRODUCTION | rights, originality, technical, and content review complete |
| BLOCKED | must not be included in a build |
| RETIRED | previously approved but no longer used; evidence retained |

## Shippable asset inventory

No production entries yet.

When adding an asset, insert a row before the placeholder and attach the evidence described below.

| Registry ID | Type / title | Creator / owner | Source and acquired date | License / rights | Evidence reference | Modified? | Roblox asset ID | Used in | Status / approver / date |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| — | No external/imported production asset registered | — | — | — | — | — | — | — | BLOCKED until a real row is approved |

Use stable registry IDs such as CHR-001, WPN-001, MAP-001, UI-001, ANIM-001, SFX-001, MUS-001, MKT-001, and FONT-001. Never reuse an ID for a different asset.

## Project-original work record

For employee/owner-created work, record:

- human creator and date range;
- written brief and source file path;
- confirmation that no protected asset was traced/extracted;
- any reference set, marked reference-only;
- tools and any third-party brushes, fonts, samples, or generators used;
- contributor/ownership agreement when the creator is not the project owner;
- export hash/version and Roblox asset ID;
- originality, technical, and release approvers.

“Made in-house” does not resolve rights to embedded fonts, samples, stock textures, brushes, or generated inputs; register those dependencies too.

## Commissioned work

Before work starts, retain a written agreement covering:

- parties and exact deliverables;
- payment and whether transfer/license is conditional on payment;
- commercial, modification, sublicensing/distribution, marketing, platform, territory, and duration rights;
- creator warranties about originality and disclosed third-party inputs;
- permission for source-file delivery and future edits;
- credit obligations;
- AI/tool usage disclosure;
- termination/takedown and infringement cooperation.

Do not paste private contracts or personal addresses into this public repository. Store them in restricted project storage and put a non-sensitive evidence ID, date, owner, and integrity hash in the registry.

## Third-party asset review

For licensed stock/marketplace/library assets, verify:

1. Exact asset, creator, publisher, and canonical source.
2. License text/version on the acquisition date.
3. Commercial use, modification, redistribution inside a Roblox experience, and marketing rights.
4. Attribution, notice, share-alike, source, or no-endorsement obligations.
5. Restrictions on games, virtual goods, resale, ML training, age/audience, territory, or number of seats.
6. Whether the Roblox uploader actually owns/controls the rights.
7. Whether audio covers composition, master recording, performance, and samples.
8. Whether the final use introduces trademark, character, privacy, or publicity issues.
9. Evidence screenshot/PDF/receipt kept in restricted storage when needed.

Record every obligation in the shipped notices/credits and release checklist. If the license can change online, retain the version obtained on the acquisition date.

## AI-assisted assets

AI output may be used only as an editable starting point after documenting:

- provider/model/tool and date;
- account tier and applicable commercial terms;
- whether input/output may be retained or used for training;
- every uploaded reference and proof it was authorized;
- export/use restrictions and attribution;
- human redesign, retopology, repainting, and originality review;
- known provenance uncertainty.

Do not upload reference-game screenshots to reproduce protected characters, maps, weapons, UI, or promotional art. Do not publish raw/unreviewed generated output. Legal review may reject AI output even when provider terms permit commercial use.

## Fonts

- Prefer platform-provided fonts or a deliberately licensed font family.
- Register any imported font file and include embedding/subsetting/attribution requirements.
- Do not assume a font is free because it is available in a design tool.
- Confirm interface and marketing usage separately when their pipelines differ.

## Audio

Each audio entry must distinguish:

- composition rights;
- master recording rights;
- performer/voice consent;
- sample/loop/plugin-library license;
- platform upload/monetization rights;
- required credits and content restrictions.

No Wild Ones music, melody, sound effect, voice, or extracted audio is allowed. Temporary sounds must be clearly marked and removed or approved before publication.

## Reference-only register

Reference material is never copied into the game or public marketing. Keep it outside production import paths and record why it is present.

| Reference ID | Subject | Lawful source | Purpose | Storage | Production exclusion verified |
| --- | --- | --- | --- | --- | --- |
| — | No reference package registered | — | — | — | Yes |

Screenshots supplied by the owner may be analyzed for general composition, contrast, hierarchy, timing, and emotional tone, but not traced, extracted, or used as generative reconstruction inputs.

## Evidence and repository policy

- Public repository: this registry, non-sensitive source links, attribution, licenses that must accompany distribution, hashes, and approval status.
- Restricted project storage: receipts, contracts, identity/contact details, private invoices, signed releases, and confidential correspondence.
- Asset source directories: editable project files and approved exports where size/licensing permits.
- Roblox: uploaded asset ID, owning user/group, moderation status, and experience permission.

Never commit passwords, tokens, private contract data, or unrestricted upload credentials.

## Import checklist

- [ ] Stable registry ID assigned.
- [ ] Creator and canonical source identified.
- [ ] License/ownership evidence captured with date/version.
- [ ] Intended commercial Roblox and marketing use permitted.
- [ ] Attribution/notice/source obligations recorded.
- [ ] Embedded font/sample/texture/brush/tool inputs reviewed.
- [ ] Originality/IP/trademark/privacy review passes.
- [ ] Editable source and approved export retained.
- [ ] Technical budgets, collision, pivots, naming, and moderation pass.
- [ ] Roblox asset ID and owner recorded.
- [ ] Private/Production approval and date recorded.

## Release reconciliation

Before each publish:

1. Extract every mesh, texture/image, animation, audio, font, plugin-generated output, and marketing asset referenced by the release.
2. Match each to an APPROVED row and exact Roblox asset ID/export hash.
3. Confirm reference-only/BLOCKED/PENDING assets are absent.
4. Generate required credits/notices and preserve evidence.
5. Record the registry revision/commit in the release record.

Any mismatch blocks publication.
