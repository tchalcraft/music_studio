defmodule MusicStudio.Leads.Lead do
  @moduledoc """
  A prospective-student inquiry captured from the site's contact form.

  Kept intentionally small and independent of the CMS (Beacon) so it survives a
  future migration of lead handling to Buzz.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @instruments ~w(voice piano guitar)
  @statuses [:new, :contacted, :converted, :lost]

  # Note: this table predates the UUIDv7 data model, so it keeps its bigint primary key
  # and default (naive) timestamps. `converted_student_id` links the funnel forward to a
  # UUIDv7 `students` row.
  schema "leads" do
    field :name, :string
    field :email, :string
    field :instrument, :string
    field :message, :string
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :source, :string
    field :converted_student_id, Ecto.UUID

    timestamps()
  end

  @doc "The instruments a prospective student can inquire about."
  def instruments, do: @instruments

  @doc "Funnel statuses for a lead."
  def statuses, do: @statuses

  @doc false
  def changeset(lead, attrs) do
    lead
    |> cast(attrs, [:name, :email, :instrument, :message])
    |> update_change(:name, &trim/1)
    |> update_change(:email, &downcase_trim/1)
    |> update_change(:instrument, &downcase_trim/1)
    |> validate_required([:name, :email, :instrument])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:message, max: 2000)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email")
    |> validate_inclusion(:instrument, @instruments, message: "must be voice, piano, or guitar")
  end

  @doc """
  Changeset for internal funnel updates (status, source, conversion link) — kept separate
  from `changeset/2` so the public inquiry form can't set these fields.
  """
  def funnel_changeset(lead, attrs) do
    lead
    |> cast(attrs, [:status, :source, :converted_student_id])
    |> validate_required([:status])
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp downcase_trim(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp downcase_trim(value), do: value
end
