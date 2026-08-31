defmodule MusicStudio.CatalogTest do
  use MusicStudio.DataCase, async: true

  alias MusicStudio.Catalog
  alias MusicStudio.Catalog.Instrument

  describe "instruments" do
    test "create_instrument/1 normalizes the slug and persists" do
      assert {:ok, %Instrument{} = i} =
               Catalog.create_instrument(%{name: "Voice", slug: " Voice "})

      assert i.slug == "voice"
      assert i.active
    end

    test "create_instrument/1 enforces a unique slug" do
      {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano"})
      assert {:error, changeset} = Catalog.create_instrument(%{name: "Piano 2", slug: "piano"})
      assert "has already been taken" in errors_on(changeset).slug
    end

    test "list_instruments/0 excludes soft-deleted rows" do
      {:ok, keep} = Catalog.create_instrument(%{name: "Guitar", slug: "guitar"})
      {:ok, gone} = Catalog.create_instrument(%{name: "Drums", slug: "drums"})
      {:ok, _} = Catalog.update_instrument(gone, %{deleted_at: DateTime.utc_now()})

      slugs = Catalog.list_instruments() |> Enum.map(& &1.slug)
      assert keep.slug in slugs
      refute gone.slug in slugs
    end
  end

  describe "offerings" do
    test "create_offering/1 requires positive duration and price" do
      assert {:error, changeset} =
               Catalog.create_offering(%{
                 name: "Bad",
                 duration_minutes: 0,
                 price_cents: -1,
                 currency: "CAD"
               })

      assert errors_on(changeset).duration_minutes != []
      assert errors_on(changeset).price_cents != []
    end

    test "create_offering/1 persists a valid rate" do
      assert {:ok, o} =
               Catalog.create_offering(%{
                 name: "60-minute lesson",
                 duration_minutes: 60,
                 price_cents: 6000,
                 currency: "CAD"
               })

      assert o.price_cents == 6000
      assert o.currency == "CAD"
    end
  end
end
