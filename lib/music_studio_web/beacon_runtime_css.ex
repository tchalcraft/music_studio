defmodule MusicStudioWeb.BeaconRuntimeCSS do
  @moduledoc """
  A lightweight CSS compiler for the Beacon site (`Beacon.RuntimeCSS` behaviour).

  Beacon 0.5.1's built-in `Beacon.RuntimeCSS.TailwindCompiler` assumes Tailwind v3
  (it emits `@import "tailwindcss/base"`), which fails against this app's Tailwind v4
  binary. Rather than downgrade the whole app's frontend to v3, we bypass the runtime
  Tailwind run and serve a small readable base stylesheet, so Beacon boots and serves
  CMS content from the database. Full Tailwind-driven styling of Beacon pages is a
  follow-up (see checkpoint "Beacon" notes).
  """
  @behaviour Beacon.RuntimeCSS

  @impl Beacon.RuntimeCSS
  def config(_site), do: ""

  @impl Beacon.RuntimeCSS
  def compile(_site) do
    {:ok, base_css()}
  end

  defp base_css do
    """
    :root { --ms-accent: #3e63dd; --ms-text: #1c2024; --ms-muted: #60646c; }
    *, *::before, *::after { box-sizing: border-box; }
    body { margin: 0; font-family: Inter, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; line-height: 1.6; color: var(--ms-text); }
    main, .container { max-width: 64rem; margin-inline: auto; padding: 1.5rem; }
    h1, h2, h3 { line-height: 1.2; letter-spacing: -0.02em; }
    a { color: var(--ms-accent); }
    img { max-width: 100%; height: auto; }
    """
  end
end
