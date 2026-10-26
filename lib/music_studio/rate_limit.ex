defmodule MusicStudio.RateLimit do
  @moduledoc """
  In-memory (ETS) rate limiter for the public forms, via Hammer.

  Single-node by design: the app runs as one Render instance, and counters resetting on a
  restart is acceptable for abuse throttling.

  `hit/3` is Hammer's: `{:allow, count} | {:deny, ms_until_reset}`. Callers go through
  `allow?/3`, which also honours `config :music_studio, MusicStudio.RateLimit, enabled: false`
  (the test env), so ordinary tests can submit forms freely.
  """
  use Hammer, backend: :ets

  @doc "True if `key` is still under `limit` hits per `scale_ms`. Counts this attempt."
  def allow?(key, scale_ms, limit) do
    if enabled?() do
      match?({:allow, _count}, hit(key, scale_ms, limit))
    else
      true
    end
  end

  defp enabled? do
    :music_studio |> Application.get_env(__MODULE__, []) |> Keyword.get(:enabled, true)
  end
end
