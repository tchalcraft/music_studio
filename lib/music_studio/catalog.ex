defmodule MusicStudio.Catalog do
  @moduledoc """
  Reference/dimension data: teachers, locations, instruments, and offerings (the rate
  card). Relatively static, seeded at setup, and referenced by the teaching and billing
  domains. All list functions exclude soft-deleted rows.
  """
  import Ecto.Query, warn: false

  alias MusicStudio.Catalog.Instrument
  alias MusicStudio.Catalog.Location
  alias MusicStudio.Catalog.Offering
  alias MusicStudio.Catalog.Teacher
  alias MusicStudio.Repo

  ## Teachers

  def list_teachers, do: Repo.all(active_scope(Teacher))
  def get_teacher!(id), do: Repo.get!(Teacher, id)
  def change_teacher(%Teacher{} = t \\ %Teacher{}, attrs \\ %{}), do: Teacher.changeset(t, attrs)

  def create_teacher(attrs \\ %{}), do: %Teacher{} |> Teacher.changeset(attrs) |> Repo.insert()

  def update_teacher(%Teacher{} = t, attrs), do: t |> Teacher.changeset(attrs) |> Repo.update()

  ## Locations

  def list_locations, do: Repo.all(active_scope(Location))
  def get_location!(id), do: Repo.get!(Location, id)

  def change_location(%Location{} = l \\ %Location{}, attrs \\ %{}),
    do: Location.changeset(l, attrs)

  def create_location(attrs \\ %{}),
    do: %Location{} |> Location.changeset(attrs) |> Repo.insert()

  def update_location(%Location{} = l, attrs),
    do: l |> Location.changeset(attrs) |> Repo.update()

  ## Instruments

  def list_instruments, do: Repo.all(from i in active_scope(Instrument), order_by: i.name)
  def get_instrument!(id), do: Repo.get!(Instrument, id)
  def get_instrument_by_slug(slug), do: Repo.get_by(Instrument, slug: slug)

  def change_instrument(%Instrument{} = i \\ %Instrument{}, attrs \\ %{}),
    do: Instrument.changeset(i, attrs)

  def create_instrument(attrs \\ %{}),
    do: %Instrument{} |> Instrument.changeset(attrs) |> Repo.insert()

  def update_instrument(%Instrument{} = i, attrs),
    do: i |> Instrument.changeset(attrs) |> Repo.update()

  ## Offerings

  def list_offerings,
    do: Repo.all(from o in active_scope(Offering), order_by: [desc: o.duration_minutes])

  def get_offering!(id), do: Repo.get!(Offering, id)

  def change_offering(%Offering{} = o \\ %Offering{}, attrs \\ %{}),
    do: Offering.changeset(o, attrs)

  def create_offering(attrs \\ %{}),
    do: %Offering{} |> Offering.changeset(attrs) |> Repo.insert()

  def update_offering(%Offering{} = o, attrs),
    do: o |> Offering.changeset(attrs) |> Repo.update()

  # Excludes soft-deleted rows. Used by all list_* functions.
  defp active_scope(queryable), do: from(r in queryable, where: is_nil(r.deleted_at))
end
