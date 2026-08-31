defmodule MusicStudio.Analytics do
  @moduledoc """
  Analytics domain: the append-only event stream plus read access to the reporting views
  (`analytics_lesson_facts`, `analytics_funnel`) created in migrations.

  `record_event/1` is the single write path other contexts use to log domain events
  (e.g. a lead created, a lesson completed). Reads go through the SQL views so BI-shaped
  queries stay decoupled from the normalized tables.
  """
  import Ecto.Query, warn: false

  alias MusicStudio.Analytics.Event
  alias MusicStudio.Repo

  ## Event stream (append-only)

  @doc """
  Records a domain event. Accepts a map with at least `:verb` and `:subject_type`, plus
  optional `:actor_type`, `:actor_id`, `:subject_id`, `:occurred_at`, `:metadata`.
  """
  def record_event(attrs) do
    %Event{}
    |> Event.changeset(normalize(attrs))
    |> Repo.insert()
  end

  @doc "Lists recorded events, newest first (optionally limited)."
  def list_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    Repo.all(from e in Event, order_by: [desc: e.occurred_at], limit: ^limit)
  end

  @doc "Lists events about a given subject, newest first."
  def list_events_for(subject_type, subject_id) do
    Repo.all(
      from e in Event,
        where:
          e.subject_type == ^to_string(subject_type) and e.subject_id == ^to_string(subject_id),
        order_by: [desc: e.occurred_at]
    )
  end

  ## Reporting views (hybrid marts)

  @doc "Returns rows from the `analytics_lesson_facts` view as maps."
  def lesson_facts, do: rows_as_maps("SELECT * FROM analytics_lesson_facts")

  @doc "Returns rows from the `analytics_funnel` view as maps."
  def funnel, do: rows_as_maps("SELECT * FROM analytics_funnel")

  # `sql` is only ever a hardcoded literal from the two functions above (no interpolation
  # or user input), so this is not an injection vector. (Sobelow low-confidence flag.)
  # sobelow_skip ["SQL.Query"]
  defp rows_as_maps(sql) do
    %{columns: cols, rows: rows} = Repo.query!(sql)
    Enum.map(rows, fn row -> cols |> Enum.zip(row) |> Map.new() end)
  end

  # Accept string- or atom-keyed maps; stringify id-ish values for the generic columns.
  defp normalize(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> stringify("actor_id")
    |> stringify("subject_id")
  end

  defp stringify(map, key) do
    case Map.get(map, key) do
      nil -> map
      value -> Map.put(map, key, to_string(value))
    end
  end
end
