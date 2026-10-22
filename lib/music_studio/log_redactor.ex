defmodule MusicStudio.LogRedactor do
  @moduledoc """
  A primary `:logger` filter that scrubs booking manage tokens from log lines.

  A manage link (`/book/manage/<token>`) lets whoever holds it cancel or reschedule that
  booking, and Phoenix logs every request path at `:info`. Without this, the Render log
  stream is a list of working manage links.
  """

  @token_path ~r{/book/manage/[A-Za-z0-9_\-]+}
  @replacement "/book/manage/[FILTERED]"

  @doc "Installs the filter. Idempotent."
  def install do
    case :logger.add_primary_filter(__MODULE__, {&__MODULE__.filter/2, []}) do
      :ok -> :ok
      {:error, {:already_exist, _}} -> :ok
    end
  end

  @doc false
  def filter(%{msg: msg} = event, _opts), do: %{event | msg: redact_msg(msg)}

  defp redact_msg({:string, chardata}), do: {:string, redact(chardata)}

  defp redact_msg({format, args}) when is_list(args) do
    {:string, format |> :io_lib.format(args) |> redact()}
  rescue
    _ -> {format, args}
  end

  defp redact_msg(other), do: other

  @doc false
  def redact(chardata) do
    string = IO.chardata_to_string(chardata)

    if String.contains?(string, "/book/manage/"),
      do: Regex.replace(@token_path, string, @replacement),
      else: chardata
  end
end
