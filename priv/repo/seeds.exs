# Seeds the reference/dimension data for the music_studio domain model.
#
# Run with:  mix run priv/repo/seeds.exs   (also run by `mix ecto.setup`)
#
# Idempotent: each insert is guarded by an existence check (keyed on a natural key),
# so re-running never creates duplicates.

alias MusicStudio.Catalog
alias MusicStudio.Catalog.Instrument
alias MusicStudio.Catalog.Location
alias MusicStudio.Catalog.Offering
alias MusicStudio.Catalog.Teacher
alias MusicStudio.Repo

upsert = fn queryable, natural_key, create_fun ->
  case Repo.get_by(queryable, natural_key) do
    nil ->
      {:ok, record} = create_fun.()
      record

    existing ->
      existing
  end
end

# Teacher
upsert.(Teacher, [email: "tristan@example.com"], fn ->
  Catalog.create_teacher(%{
    name: "Tristan",
    email: "tristan@example.com",
    bio: "Classically trained teacher of voice, piano, and guitar.",
    active: true
  })
end)

# Location (the in-person studio)
upsert.(Location, [name: "Studio"], fn ->
  Catalog.create_location(%{name: "Studio", kind: :in_person, active: true})
end)

# Instruments
for {name, slug} <- [{"Voice", "voice"}, {"Piano", "piano"}, {"Guitar", "guitar"}] do
  upsert.(Instrument, [slug: slug], fn ->
    Catalog.create_instrument(%{name: name, slug: slug, active: true})
  end)
end

# Offerings — the rate card (CAD)
for {name, minutes, cents} <- [
      {"60-minute lesson", 60, 6000},
      {"45-minute lesson", 45, 4500},
      {"30-minute lesson", 30, 3000}
    ] do
  upsert.(Offering, [name: name], fn ->
    Catalog.create_offering(%{
      name: name,
      duration_minutes: minutes,
      price_cents: cents,
      currency: "CAD",
      active: true
    })
  end)
end

IO.puts("Seeded reference data: teachers, locations, instruments, offerings.")
