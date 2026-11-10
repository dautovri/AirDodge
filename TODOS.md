# TODOS — Neckline 2.0 (formerly AirBoxer)

Version 2.0 rewrites the boxing game as **Neckline**, a posture and neck-mobility
coach. It keeps the bundle ID `com.airdodge.AirpodsGame`, the App Store record
(app id 6772939322) and the headphone-motion engine (`Core/MotionManager.swift`).

## Before submitting 2.0 (App Store Connect, human steps)

1. **Subscriptions.** Create the subscription group "Neckline Pro" with:
   - `com.airdodge.AirpodsGame.pro.yearly` (with a 1-week free trial as the
     introductory offer; this is the default plan on the paywall)
   - `com.airdodge.AirpodsGame.pro.monthly`
   Until these exist, `SubscriptionStoreView` shows no plans.
2. **Rename the listing:** name "Neckline: Posture Coach", subtitle "Tech-neck
   alerts & stretches", category Health & Fitness (primary). Copy is in
   `metadata/app-info/en-US.json` and `metadata/version/2.0/en-US.json`.
3. **Listing translations** for all 11 locales are in `metadata/app-info/` and
   `metadata/version/2.0/` (machine-translated; get a native check for your top markets).
4. **In-app strings** are translated for the same locales in `Localizable.xcstrings`
   (also machine-translated). Local purchase testing: `AirpodsGame/Neckline.storekit`
   (yearly 29.99 with a 1-week trial, monthly 4.99); confirm the scheme picks it up
   under Run > Options > StoreKit Configuration.
5. **Game Center:** the app no longer uses it. Remove the Game Center capability
   from the App ID and archive the leaderboards in ASC.
6. **The old `fullcard` non-consumable** is unused. Remove it from sale.
7. **Screenshots + preview:** `marketing/` holds AirBoxer assets only. Capture new
   ones with `-ABFakeMotion -NLPro` (DEBUG launch arguments).
8. **Privacy policy page** (`dautovri.com/airboxer-privacy`) still names
   AirBoxer. Update it, or move it to a Neckline URL and change `ProStore.privacyURL`.
9. **Review notes:** posture sessions need head-tracking headphones. Routines and
   the paywall work without them (guided mode). Say so in the App Review notes.

## Verify on device

- **Yaw sign.** `Movement.turnLeft` expects yaw to be positive when turning left
  (CoreMotion is counter-clockwise-positive). Confirm with real earbuds and flip
  the signs in `Movement.amount` if needed. Pitch and roll signs carry over from
  AirBoxer, where they were verified on device.
- Check that the voice nudge ducks music correctly over Bluetooth.

## Next (retention / MRR)

- **Background posture monitoring.** Sessions run only while the app is open
  (screen stays awake). Look into a Live Activity plus a sanctioned background mode.
  Silent-audio tricks get rejected.
- Home-screen widget showing the streak and today's upright %.
- Daily reminder notification for the reset routine (opt-in).
- HealthKit: log routines as "Mind & Body" minutes.
- A/B test the paywall shown at the end of onboarding against a delayed paywall.
