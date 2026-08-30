defmodule MusicStudio.LeadsTest do
  use MusicStudio.DataCase, async: true

  import Swoosh.TestAssertions

  alias MusicStudio.Leads
  alias MusicStudio.Leads.Lead
  alias MusicStudio.Leads.Notifier

  @valid %{
    name: "Jane Doe",
    email: "Jane@Example.com ",
    instrument: "Voice",
    message: "Interested in weekly voice lessons"
  }

  describe "create_lead/1" do
    test "persists a valid inquiry, normalizing email and instrument" do
      assert {:ok, %Lead{} = lead} = Leads.create_lead(@valid)
      assert lead.name == "Jane Doe"
      assert lead.email == "jane@example.com"
      assert lead.instrument == "voice"
      assert lead.message == "Interested in weekly voice lessons"
    end

    test "requires name, email, and instrument" do
      assert {:error, changeset} = Leads.create_lead(%{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.name
      assert "can't be blank" in errors.email
      assert "can't be blank" in errors.instrument
    end

    test "rejects an invalid email" do
      assert {:error, changeset} = Leads.create_lead(%{@valid | email: "not-an-email"})
      assert "must be a valid email" in errors_on(changeset).email
    end

    test "rejects an unsupported instrument" do
      assert {:error, changeset} = Leads.create_lead(%{@valid | instrument: "tuba"})
      assert "must be voice, piano, or guitar" in errors_on(changeset).instrument
    end

    test "message is optional" do
      assert {:ok, %Lead{} = lead} = Leads.create_lead(Map.delete(@valid, :message))
      assert lead.message == nil
    end
  end

  describe "list_leads/0" do
    test "returns inquiries newest first" do
      {:ok, _first} = Leads.create_lead(@valid)
      {:ok, _second} = Leads.create_lead(%{@valid | name: "Second Student"})

      assert [%Lead{name: "Second Student"}, %Lead{name: "Jane Doe"}] = Leads.list_leads()
    end
  end

  describe "Notifier.deliver_inquiry_notification/1" do
    test "emails the configured address, reply-to the inquirer" do
      {:ok, lead} = Leads.create_lead(@valid)

      assert {:ok, _email} = Notifier.deliver_inquiry_notification(lead)

      assert_email_sent(fn email ->
        assert email.subject == "New lesson inquiry from Jane Doe"
        assert {_name, "jane@example.com"} = email.reply_to
        assert email.text_body =~ "Instrument: Voice"
      end)
    end
  end
end
