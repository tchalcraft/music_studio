defmodule MusicStudio.Turnstile do
  @moduledoc """
  Server-side verification of Cloudflare Turnstile tokens (the bot check on public forms).

  Config: `config :music_studio, :turnstile, site_key: …, secret_key: …` (prod:
  `TURNSTILE_SITE_KEY` / `TURNSTILE_SECRET_KEY`). With no `secret_key` the check is off
  (dev/test), and the widget isn't rendered either.

  A token Cloudflare rejects fails the submit. If Cloudflare itself can't be reached, the
  submit is **allowed** and a warning logged: losing a real booking costs more than
  letting through a request during an outage spammers can't trigger. The per-IP rate
  limit still applies either way.
  """
  require Logger

  @siteverify "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc "The public site key for the widget, or nil when Turnstile is off."
  def site_key, do: if(enabled?(), do: config()[:site_key])

  @doc "Verifies a widget token. `:ok` or `{:error, reason}`."
  def verify(token, remote_ip \\ nil) do
    cond do
      not enabled?() -> :ok
      token in [nil, ""] -> {:error, :missing_token}
      true -> siteverify(token, remote_ip)
    end
  end

  defp siteverify(token, remote_ip) do
    form = [secret: config()[:secret_key], response: token] ++ remote_ip_param(remote_ip)

    opts =
      [form: form, receive_timeout: 5_000, retry: false]
      |> Keyword.merge(config()[:req_options] || [])

    case Req.post(@siteverify, opts) do
      {:ok, %{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %{status: 200, body: %{"success" => false} = body}} ->
        {:error, {:rejected, body["error-codes"] || []}}

      other ->
        Logger.warning("Turnstile siteverify unavailable, allowing submit: #{inspect(other)}")
        :ok
    end
  end

  defp remote_ip_param(ip) when is_binary(ip) and ip != "", do: [remoteip: ip]
  defp remote_ip_param(_ip), do: []

  defp enabled?, do: config()[:secret_key] not in [nil, ""]

  defp config, do: Application.get_env(:music_studio, :turnstile, [])
end
