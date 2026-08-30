defmodule MusicStudio.Leads do
  @moduledoc """
  The Leads context: capturing and reading prospective-student inquiries from the
  public site's contact form.

  Deliberately self-contained (schema + changeset + persistence) and independent of
  the CMS, so it can be reused or replaced (e.g. by Buzz) without touching page code.
  Email notification lives in `MusicStudio.Leads.Notifier` and is triggered by callers
  after a successful `create_lead/1`, keeping this context free of mail side effects.
  """
  import Ecto.Query, only: [from: 2]

  alias MusicStudio.Leads.Lead
  alias MusicStudio.Repo

  @doc "Lists inquiries, newest first."
  def list_leads do
    Repo.all(from l in Lead, order_by: [desc: l.inserted_at, desc: l.id])
  end

  @doc "Fetches a single lead by id, raising if missing."
  def get_lead!(id), do: Repo.get!(Lead, id)

  @doc "Builds a changeset for a lead, for form rendering/validation."
  def change_lead(%Lead{} = lead \\ %Lead{}, attrs \\ %{}) do
    Lead.changeset(lead, attrs)
  end

  @doc """
  Validates and persists an inquiry.

  Returns `{:ok, lead}` or `{:error, changeset}`. Sending the notification email is
  the caller's responsibility (see `MusicStudio.Leads.Notifier`).
  """
  def create_lead(attrs \\ %{}) do
    %Lead{}
    |> Lead.changeset(attrs)
    |> Repo.insert()
  end
end
