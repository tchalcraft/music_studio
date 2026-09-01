defmodule MusicStudio.Billing.StripeTest do
  # async: false — these tests mutate the global :stripe application env.
  use ExUnit.Case, async: false

  alias MusicStudio.Billing.Stripe

  describe "health_check/0" do
    setup do
      original = Application.get_env(:music_studio, :stripe)
      on_exit(fn -> Application.put_env(:music_studio, :stripe, original) end)
      {:ok, original: original || []}
    end

    test "returns {:error, :missing_secret_key} when no key is configured", %{original: original} do
      Application.put_env(:music_studio, :stripe, Keyword.put(original, :secret_key, nil))
      assert {:error, :missing_secret_key} = Stripe.health_check()
    end

    test "treats a blank secret key as missing", %{original: original} do
      Application.put_env(:music_studio, :stripe, Keyword.put(original, :secret_key, ""))
      assert {:error, :missing_secret_key} = Stripe.health_check()
    end
  end
end
