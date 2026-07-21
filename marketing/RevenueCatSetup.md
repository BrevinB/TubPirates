# RevenueCat Setup — Tub Pirates

The code side is done: the SDK is integrated, `StoreService` wraps it, and the
Doubloon Merchant sheet is live behind the menu's coin chip. With no API key
set the store stays safely "asleep." This checklist is the external work.

## 1. RevenueCat account (free up to $2.5k MTR)
- [ ] Create account at app.revenuecat.com → new Project "Tub Pirates"
- [ ] Add an App Store app with bundle ID `co.brevinb.TubPirates`
- [ ] Copy the **public Apple API key** (`appl_…`) into
      `StoreService.apiKey` (TubPirates/Store/StoreService.swift)

## 2. App Store Connect
- [ ] Sign the **Paid Applications agreement** (Agreements, Tax, Banking) —
      nothing works until this is active
- [ ] Create the app record under `co.brevinb.TubPirates` (if not already)
- [ ] Create three **Consumable** in-app purchases:

| Product ID | Reference name | Price tier | Grants |
|---|---|---|---|
| `co.brevinb.TubPirates.doubloons.handful` | Handful o' Doubloons | $0.99 | 600 |
| `co.brevinb.TubPirates.doubloons.chest` | Chest o' Doubloons | $2.99 | 2,000 |
| `co.brevinb.TubPirates.doubloons.hoard` | Hoard o' Doubloons | $5.99 | 5,000 |

  (Value curve: ~600/$ → ~670/$ → ~830/$ — bigger packs reward commitment.
  Coin amounts are mirrored in `StoreService.coinAmounts`; change both places
  or nothing is granted.)
- [ ] Each IAP needs a display name, description, and a review screenshot
      (screenshot of the Doubloon Merchant sheet works)
- [ ] Generate an **In-App Purchase Key** (Users & Access → Integrations) and
      upload it to RevenueCat (required for StoreKit 2)

## 3. RevenueCat dashboard wiring
- [ ] Import/attach the three products
- [ ] Create an **Offering** named `default` with three packages
      (custom identifiers are fine) — one per product
- [ ] The app reads `offerings.current`, so mark it as the current offering

## 4. Testing
- [ ] Sandbox tester account (App Store Connect → Users & Access → Sandbox)
- [ ] On a device/simulator signed into the sandbox account: buy each pack,
      verify balance increases and the chest jingle plays
- [ ] Kill the app mid-purchase and relaunch — RevenueCat replays unfinished
      transactions; confirm no double-grant (grants key off the purchase
      callback, which fires once)
- [ ] Verify the "merchant be asleep" state by blanking the API key

## 5. App Review notes
- Consumables only — **no Restore button required** (Guideline 3.1.1 restore
  applies to non-consumables/subscriptions)
- Add to review notes: "In-app purchases are consumable coin packs handled by
  RevenueCat. No account/login required."
- Privacy nutrition label changes: RevenueCat collects **Purchases** data
  (purchase history) linked via an anonymous ID → declare "Purchases" as
  collected, not linked to identity, not used for tracking. Update
  `marketing/AppStoreListing.md` privacy section when the store ships.

## Design guardrails already in code
- Coin packs only — no direct-buy of items, keeping one currency and one economy
- Purchases grant instantly to the local profile (no server dependency)
- Store absent = zero UI degradation (the chip still shows balance; the sheet
  explains packs are coming)
- No purchase prompts pushed at children: the shop is only behind the coin
  chip; the mid-battle/defeat offers spend earned doubloons, never money
