defmodule MusicStudio.Schema do
  @moduledoc """
  Base schema for the domain data model.

  Centralizes the conventions that keep the model consistent and ready for an eventual
  lakehouse (Databricks/Delta) via CDC-friendly ingestion:

    * **UUIDv7 primary/foreign keys** — globally unique and time-sortable, so rows merge
      cleanly across systems and index locality stays good (unlike random UUIDv4).
    * **Microsecond UTC timestamps** — `inserted_at`/`updated_at` as `:utc_datetime_usec`,
      giving a reliable high-watermark for incremental extraction.

  Use it in place of `use Ecto.Schema`:

      defmodule MusicStudio.Catalog.Teacher do
        use MusicStudio.Schema
        schema "teachers" do
          field :name, :string
          timestamps()
        end
      end

  Other shared conventions (documented, applied per-schema): a `deleted_at` soft-delete
  column on mutable entities, `Ecto.Enum` stored as strings, integer `*_cents` money with
  a `currency` string, and `:map` (jsonb) `metadata`. The pre-existing `leads` table keeps
  its bigint key and uses plain `Ecto.Schema`.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, UUIDv7, autogenerate: true}
      @foreign_key_type UUIDv7
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
