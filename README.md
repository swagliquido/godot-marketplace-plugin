# GodotArchive Publisher

One-click publishing from the Godot editor to [GodotArchive](https://godotarchive.com) — an itch.io-style marketplace built specifically for Godot HTML5 games.

## Install

1. Download the latest release (or clone this repo).
2. Copy `addons/godotarchive_publisher/` into your project's `addons/` directory.
3. Godot → **Project → Project Settings → Plugins → GodotArchive Publisher → Enable**.
4. A new **GodotArchive** dock appears in the bottom-right panel.

## Configure your API key

1. Sign in at [godotarchive.com](https://godotarchive.com) and open **Settings → Developer → API keys**.
2. Create a key scoped to **Publish**. Copy it.
3. In Godot: **Editor → Editor Settings → godotarchive → Api Key** → paste it.

The plugin's status line should flip to **Connected**.

## Publish a game

1. Export your game as **HTML5** from **Project → Export** (any path — the plugin zips it for you).
2. In the dock, fill in Title, Description, Tags, Genre, and Price.
3. **HTML5 export dir** → point at the folder containing `index.html`.
4. Click **Upload to GodotArchive**. The plugin zips, uploads, and enqueues for review.

A submission goes through moderation before it's publicly searchable. The queue is human — the site owner is emailed on every submission and typically responds within 24 h. Click **My submissions** in the dock to check status without leaving Godot.

## Pricing options

- **Free** — unlimited downloads + plays, 0 % cut.
- **Pay-what-you-want** — players choose any price ≥ €0, 5 % platform cut on paid transactions only.
- **Fixed price** — minimum €0.50, 10 % platform cut. Flip to 3 % on a paid creator plan.

Payments route through Stripe; GodotArchive never holds payout funds. Your Stripe Connect account (set up once on the site) receives the net amount directly.

## Troubleshooting

- **Connected but uploads 401** — your API key may have been revoked. Regenerate on the site and re-paste.
- **"Directory does not exist"** — export to an *absolute* path, not `res://`. `res://` doesn't exist on disk for a plain export.
- **Upload times out on large exports** — the plugin's HTTPRequest timeout is 120 s. For exports >200 MB, upload via the website instead.

## License

MIT. See `LICENSE`.
