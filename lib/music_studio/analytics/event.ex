defmodule MusicStudio.Analytics.Event do
  @moduledoc """
  An append-only domain event (activity-stream row). Immutable: it carries `occurred_at`
  and `inserted_at` but no `updated_at`/`deleted_at`. This is the behavioral fact source
  that maps directly onto a lakehouse event/fact table.

  Shape is deliberately generic: `actor` (who), `verb` (what happened), `subject` (to what),
  and free-form `metadata` (jsonb). Actor/subject ids are stored as strings so any entity —
  UUIDv7 or the bigint lead — can be referenced without a hard FK.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  schema "events" do
    field :actor_type, :string
    field :actor_id, :string
    field :verb, :string
    field :subject_type, :string
    field :subject_id, :string
    field :occurred_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    # Append-only: only the insertion time, no updated_at.
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :actor_type,
      :actor_id,
      :verb,
      :subject_type,
      :subject_id,
      :occurred_at,
      :metadata
    ])
    |> validate_required([:verb, :subject_type])
    |> put_default_occurred_at()
  end

  defp put_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
