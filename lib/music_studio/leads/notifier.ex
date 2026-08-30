defmodule MusicStudio.Leads.Notifier do
  @moduledoc """
  Sends the teacher an email when a new inquiry arrives.

  The destination address is configuration, not code: set
  `config :music_studio, MusicStudio.Leads, inquiry_to: "..."`. In production it comes
  from an env var (see `config/runtime.exs`); locally it can be overridden in
  `config/dev.secret.exs`. Never hard-code a real address here.
  """
  import Swoosh.Email

  alias MusicStudio.Leads.Lead
  alias MusicStudio.Mailer

  @doc """
  Builds and delivers the inquiry-notification email for `lead`.

  Returns `{:ok, email}` on success or `{:error, reason}` from the mailer.
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

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
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
