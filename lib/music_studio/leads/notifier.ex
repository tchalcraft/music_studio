defmodule MusicStudio.Leads.Notifier do
  @moduledoc """
  Sends the teacher an email when a new inquiry arrives.

  The destination address is configuration, not code: set
  `config :music_studio, MusicStudio.Leads, inquiry_to: "..."`. In production it comes
  from an env var (see `config/runtime.exs`); locally it can be overridden in
  `config/dev.secret.exs`. Never hard-code a real address here.
  """
  import Swoosh.Email
  require Logger

  alias MusicStudio.Leads.Lead
  alias MusicStudio.Mailer

  @doc """
  Builds and delivers the inquiry-notification email for `lead`.

  Delivery is best-effort and NEVER raises: a failing or misconfigured mailer (e.g. the
  provider rejecting the From address) returns `{:error, reason}` and is logged, rather
  than crashing the caller. The lead is already persisted by the time this is called, so
  the visitor should still see a confirmation regardless of the email outcome.

  Returns `{:ok, email}` on success or `{:error, reason}` otherwise.
  """
  def deliver_inquiry_notification(%Lead{} = lead) do
    config = Application.get_env(:music_studio, MusicStudio.Leads, [])
    to_addr = Keyword.get(config, :inquiry_to, "owner@example.com")
    from_addr = Keyword.get(config, :inquiry_from, "no-reply@musicstudio.local")

    email =
      new()
      |> to(to_addr)
      |> from({"Music Studio Website", from_addr})
      |> reply_to(lead.email)
      |> subject("New lesson inquiry from #{lead.name}")
      |> text_body(body(lead))

    case Mailer.deliver(email) do
      {:ok, _metadata} ->
        {:ok, email}

      {:error, reason} ->
        Logger.error(
          "Inquiry notification delivery failed for lead #{lead.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  rescue
    exception ->
      Logger.error(
        "Inquiry notification delivery crashed for lead #{lead.id}: " <>
          Exception.message(exception)
      )

      {:error, {:exception, exception}}
  end

  defp body(%Lead{} = lead) do
    """
    New lesson inquiry from the website:

    Name:       #{lead.name}
    Email:      #{lead.email}
    Instrument: #{String.capitalize(lead.instrument)}

    Message:
    #{lead.message || "(none provided)"}
    """
  end
end
