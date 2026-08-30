defmodule MusicStudioWeb.BeaconRuntimeCSS do
  @moduledoc """
  Tailwind-v4 runtime CSS compiler for the Beacon site (`Beacon.RuntimeCSS` behaviour).

  Beacon 0.5.1's built-in `Beacon.RuntimeCSS.TailwindCompiler` emits Tailwind **v3**
  directives (`@import "tailwindcss/base"`), which fail against this app's Tailwind **v4**
  binary. This implementation instead:

    1. gathers the site's content (components, layouts, pages, error pages) into a temp
       dir so Tailwind can scan the classes it uses (`@source`), and
    2. runs the app's Tailwind v4 CLI over a v4 input stylesheet that also carries the
       "Modern Minimal" design tokens — so Beacon-rendered pages share the same look as
       the hand-built marketing page.

  If the Tailwind CLI is unavailable or errors, it falls back to a small base stylesheet
  so a site always boots (`Beacon.Boot` raises if CSS compilation fails).
  """
  @behaviour Beacon.RuntimeCSS

  require Logger

  @impl Beacon.RuntimeCSS
  def config(_site), do: ""

  @impl Beacon.RuntimeCSS
  def compile(site) do
    {:ok, compile_with_tailwind(site)}
  rescue
    error ->
      Logger.warning("""
      BeaconRuntimeCSS: Tailwind v4 compile failed, serving base CSS.
      #{Exception.message(error)}
      """)

      {:ok, base_css()}
  end

  # Paths are all internally-constructed temp files and the command is a fixed Tailwind
  # binary with controlled args — no external input. (Sobelow low-confidence flags.)
  # sobelow_skip ["Traversal.FileModule", "CI.System"]
  defp compile_with_tailwind(site) do
    tmp_dir =
      Path.join(System.tmp_dir!(), "beacon_css_#{site}_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    try do
      write_templates!(tmp_dir, site)
      input_path = Path.join(tmp_dir, "input.css")
      output_path = Path.join(tmp_dir, "output.css")
      File.write!(input_path, input_css(tmp_dir))

      case System.cmd(Tailwind.bin_path(), ["--input", input_path, "--output", output_path],
             stderr_to_stdout: true
           ) do
        {_out, 0} -> File.read!(output_path)
        {out, code} -> raise "tailwind exited #{code}: #{out}"
      end
    after
      File.rm_rf(tmp_dir)
    end
  end

  # Write each content template to its own .html file so Tailwind v4 (`@source`) scans
  # the utility classes it references. (tmp_dir is internally constructed.)
  # sobelow_skip ["Traversal.FileModule"]
  defp write_templates!(tmp_dir, site) do
    templates =
      component_templates(site) ++
        layout_templates(site) ++ page_templates(site) ++ error_page_templates(site)

    templates
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.with_index()
    |> Enum.each(fn {template, index} ->
      File.write!(Path.join(tmp_dir, "t#{index}.html"), template)
    end)
  end

  defp component_templates(site) do
    Enum.map(Beacon.Content.list_components(site, per_page: :infinity), & &1.template)
  end

  defp layout_templates(site) do
    Enum.map(Beacon.Content.list_published_layouts(site), & &1.template)
  end

  defp page_templates(site) do
    Enum.map(Beacon.Content.list_published_pages(site, per_page: :infinity), & &1.template)
  end

  defp error_page_templates(site) do
    Enum.map(Beacon.Content.list_error_pages(site, per_page: :infinity), & &1.template)
  end

  defp input_css(source_dir) do
    """
    @import "tailwindcss" source(none);
    @source "#{source_dir}";

    #{design_tokens()}
    """
  end

  # Shared "Modern Minimal" tokens + base, mirroring assets/css/app.css so Beacon pages
  # match the marketing site.
  defp design_tokens do
    """
    :root {
      --ms-accent: #3e63dd;
      --ms-text: #1c2024;
      --ms-muted: #60646c;
      --ms-bg: #fcfcfd;
      --ms-border: #e0e1e6;
    }
    body {
      font-family: Inter, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
      color: var(--ms-text);
      background-color: var(--ms-bg);
      line-height: 1.6;
      -webkit-font-smoothing: antialiased;
    }
    """
  end

  defp base_css do
    """
    :root { --ms-accent: #3e63dd; --ms-text: #1c2024; }
    *, *::before, *::after { box-sizing: border-box; }
    body { margin: 0; font-family: Inter, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; line-height: 1.6; color: var(--ms-text); }
    main, .container { max-width: 64rem; margin-inline: auto; padding: 1.5rem; }
    h1, h2, h3 { line-height: 1.2; letter-spacing: -0.02em; }
    a { color: var(--ms-accent); }
    img { max-width: 100%; height: auto; }
    """
  end
end
