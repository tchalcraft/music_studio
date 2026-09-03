defmodule MusicStudio.Scheduling.EmailTemplate do
  @moduledoc """
  Renders branded HTML (and matching plain-text) bodies for visitor-facing booking emails.
  Table-based layout with all CSS inlined for broad email-client support. Leads with a
  typographic "Tristan" wordmark (the app has no real logo yet). Brand colors are hardcoded
  here because email cannot `@import` — keep them in sync with assets/css/app.css.
  """

  # keep in sync with assets/css/app.css (Modern Minimal tokens)
  @accent "#3e63dd"
  @page_bg "#f4f4f7"
  @panel "#ffffff"
  @border "#e0e1e6"
  @text "#1c2024"
  @muted "#60646c"
  @font ~s(-apple-system, "Inter", system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif)

  @spec html(keyword()) :: binary()
  def html(opts) do
    title = Keyword.fetch!(opts, :title)
    greeting = Keyword.get(opts, :greeting, "")
    paragraphs = Keyword.get(opts, :paragraphs, [])
    details = Keyword.get(opts, :details, [])
    cta = Keyword.get(opts, :cta)

    """
    <!doctype html>
    <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
    <body style="margin:0;padding:0;background:#{@page_bg};">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#{@page_bg};padding:24px 0;">
        <tr><td align="center">
          <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:100%;background:#{@panel};border:1px solid #{@border};border-radius:12px;overflow:hidden;font-family:#{@font};">
            <tr><td style="padding:28px 32px 8px 32px;">
              <div style="font-size:22px;font-weight:700;letter-spacing:-0.02em;color:#{@text};font-family:#{@font};">Tristan Chalcraft Music</div>
              <div style="font-size:13px;color:#{@muted};">Music lessons for every age and stage</div>
            </td></tr>
            <tr><td style="padding:12px 32px 0 32px;">
              <h1 style="margin:0;font-size:20px;color:#{@text};font-weight:700;">#{h(title)}</h1>
            </td></tr>
            <tr><td style="padding:12px 32px 0 32px;color:#{@text};font-size:15px;line-height:1.55;">
              #{if greeting != "", do: "<p style=\"margin:0 0 12px 0;\">#{h(greeting)}</p>", else: ""}
              #{Enum.map_join(paragraphs, "\n", fn p -> "<p style=\"margin:0 0 12px 0;\">#{h(p)}</p>" end)}
            </td></tr>
            #{details_block(details)}
            #{cta_block(cta)}
            #{footer_block()}
          </table>
        </td></tr>
      </table>
    </body></html>
    """
  end

  @spec text(keyword()) :: binary()
  def text(opts) do
    greeting = Keyword.get(opts, :greeting, "")
    paragraphs = Keyword.get(opts, :paragraphs, [])
    details = Keyword.get(opts, :details, [])
    cta = Keyword.get(opts, :cta)

    detail_lines = Enum.map_join(details, "\n", fn {k, v} -> "#{k}: #{v}" end)
    cta_line = if cta, do: "\n#{cta.label}: #{cta.url}", else: ""
    link_lines = Enum.map_join(footer_links(), "\n", fn {label, url} -> "#{label}: #{url}" end)

    [
      greeting,
      Enum.join(paragraphs, "\n\n"),
      detail_lines,
      cta_line,
      "\n— Tristan Chalcraft Music · Music lessons in the Greater Vancouver area",
      link_lines
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  @spec google_calendar_url(map()) :: binary()
  def google_calendar_url(%{
        title: title,
        details: details,
        location: location,
        starts_at: s,
        ends_at: e
      }) do
    query =
      URI.encode_query(%{
        "action" => "TEMPLATE",
        "text" => title,
        "details" => details,
        "location" => location,
        "dates" => "#{stamp(s)}/#{stamp(e)}"
      })

    "https://calendar.google.com/calendar/render?" <> query
  end

  @spec footer_links() :: [{String.t(), String.t()}]
  def footer_links do
    cfg = Application.get_env(:music_studio, MusicStudio.Scheduling, [])
    social = Keyword.get(cfg, :social, [])

    [
      {"Website", Keyword.get(cfg, :website_url)},
      {"Instagram", social[:instagram]},
      {"Facebook", social[:facebook]},
      {"YouTube", social[:youtube]}
    ]
    |> Enum.filter(fn {_label, url} -> is_binary(url) and url != "" end)
  end

  defp details_block([]), do: ""

  defp details_block(details) do
    rows =
      Enum.map_join(details, "\n", fn {label, value} ->
        """
        <tr>
          <td style="padding:4px 0;color:#{@muted};font-size:13px;width:110px;">#{h(label)}</td>
          <td style="padding:4px 0;color:#{@text};font-size:14px;font-weight:600;">#{h(value)}</td>
        </tr>
        """
      end)

    """
    <tr><td style="padding:16px 32px 0 32px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#{@page_bg};border:1px solid #{@border};border-radius:8px;padding:12px 16px;">
        #{rows}
      </table>
    </td></tr>
    """
  end

  defp cta_block(nil), do: ""

  defp cta_block(%{label: label, url: url}) do
    """
    <tr><td style="padding:20px 32px 4px 32px;">
      <a href="#{h(url)}" style="display:inline-block;background:#{@accent};color:#ffffff;text-decoration:none;font-size:15px;font-weight:600;padding:12px 20px;border-radius:8px;font-family:#{@font};">#{h(label)}</a>
    </td></tr>
    """
  end

  defp footer_block do
    links =
      footer_links()
      |> Enum.map_join(" &nbsp;·&nbsp; ", fn {label, url} ->
        "<a href=\"#{h(url)}\" style=\"color:#{@accent};text-decoration:none;\">#{label}</a>"
      end)

    year = Date.utc_today().year

    """
    <tr><td style="padding:24px 32px 28px 32px;border-top:1px solid #{@border};margin-top:16px;">
      #{if links != "", do: "<div style=\"font-size:13px;margin-bottom:8px;\">#{links}</div>", else: ""}
      <div style="font-size:12px;color:#{@muted};">© #{year} Tristan Chalcraft Music · Music lessons in the Greater Vancouver area.</div>
    </td></tr>
    """
  end

  defp stamp(%DateTime{} = dt) do
    dt |> DateTime.truncate(:second) |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  # Minimal HTML escaping for interpolated text.
  defp h(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
