# App Store Metadata

This folder stores localized App Store Connect text as files so release copy can be reviewed and versioned with the app.

Each locale directory can contain:

- `description.txt` -> App Store `description`, limit 4000 characters.
- `keywords.txt` -> App Store `keywords`, limit 100 bytes. Separate terms with commas and no spaces after commas.
- `promotional-text.txt` -> App Store `promotionalText`, limit 170 characters. Apple allows this to be updated without submitting a new app version.
- `support-url.txt` -> App Store `supportUrl`.
- `whats-new.txt` -> App Store `whatsNew`, limit 4000 characters. Required for version updates after the first release.

The uploader uses the App Store Connect API resource `appStoreVersionLocalizations`.

## Credentials

Create an App Store Connect API key in App Store Connect, then export:

```sh
export ASC_KEY_ID="YOUR_KEY_ID"
export ASC_ISSUER_ID="YOUR_ISSUER_ID"
export ASC_PRIVATE_KEY_PATH="$HOME/Downloads/AuthKey_YOUR_KEY_ID.p8"
export ASC_BUNDLE_ID="co.brevinb.TubPirates"
```

Keep the `.p8` private key out of the repo.

## Dry Run

Dry-run is the default. It validates character limits, authenticates, finds the app/version/localizations, and prints what would change.

```sh
ruby scripts/appstore/push-metadata.rb --version 1.0
```

To target a single locale:

```sh
ruby scripts/appstore/push-metadata.rb --version 1.0 --locale ja
```

## Apply

Pass `--apply` to create missing version localizations and patch their text:

```sh
ruby scripts/appstore/push-metadata.rb --version 1.0 --apply
```

You can also pass `--version-id APP_STORE_VERSION_ID` if you already know the App Store Connect version resource ID.

## Current Locales

- `en-US`
- `es-MX`
- `fr-FR`
- `de-DE`
- `pt-BR`
- `ja`
- `zh-Hans`
