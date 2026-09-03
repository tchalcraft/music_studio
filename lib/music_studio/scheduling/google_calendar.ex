defmodule MusicStudio.Scheduling.GoogleCalendar do
  @moduledoc """
  Thin Google Calendar API v3 client over `Req`. Reads the Availability calendar's events
  (recurrences expanded) and writes/updates/deletes booked lesson events. Authenticated
  with the access token from `Credentials.fresh_access_token/0`.
  """
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  @base "https://www.googleapis.com/calendar/v3"

  @spec list_events(String.t(), DateTime.t(), DateTime.t()) :: {:ok, [map()]} | {:error, term()}
  def list_events(calendar_id, time_min, time_max) do
    with {:ok, token} <- Credentials.fresh_access_token() do
      params = [
        singleEvents: true,
        orderBy: "startTime",
        timeMin: DateTime.to_iso8601(time_min),
        timeMax: DateTime.to_iso8601(time_max),
        maxResults: 2500
      ]

      case Req.get(req(token, url: events_url(calendar_id), params: params)) do
        {:ok, %{status: 200, body: %{"items" => items}}} -> {:ok, parse_items(items)}
        {:ok, %{status: 200, body: _}} -> {:ok, []}
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec insert_event(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def insert_event(calendar_id, attrs) do
    with {:ok, token} <- Credentials.fresh_access_token() do
      params = [sendUpdates: "none"]

      req(token, url: events_url(calendar_id), params: params, json: event_body(attrs))
      |> Req.post()
      |> created_id()
    end
  end

  @spec update_event(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def update_event(calendar_id, event_id, attrs) do
    with {:ok, token} <- Credentials.fresh_access_token() do
      params = [sendUpdates: "none"]

      req(token, url: event_url(calendar_id, event_id), params: params, json: event_body(attrs))
      |> Req.put()
      |> created_id()
    end
  end

  @spec delete_event(String.t(), String.t()) :: :ok | {:error, term()}
  def delete_event(calendar_id, event_id) do
    with {:ok, token} <- Credentials.fresh_access_token() do
      params = [sendUpdates: "none"]

      case Req.delete(req(token, url: event_url(calendar_id, event_id), params: params)) do
        {:ok, %{status: status}} when status in [200, 204, 410] -> :ok
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp event_body(a) do
    %{
      "summary" => a.summary,
      "description" => a.description,
      "location" => a.location,
      "start" => %{"dateTime" => DateTime.to_iso8601(a.starts_at), "timeZone" => a.timezone},
      "end" => %{"dateTime" => DateTime.to_iso8601(a.ends_at), "timeZone" => a.timezone}
    }
  end

  defp created_id({:ok, %{status: status, body: %{"id" => id}}}) when status in [200, 201],
    do: {:ok, id}

  defp created_id({:ok, %{status: status, body: body}}), do: {:error, {:http, status, body}}
  defp created_id({:error, reason}), do: {:error, reason}

  defp parse_items(items) do
    items
    |> Enum.filter(&get_in(&1, ["start", "dateTime"]))
    |> Enum.map(fn item ->
      %{
        starts_at: parse_dt(get_in(item, ["start", "dateTime"])),
        ends_at: parse_dt(get_in(item, ["end", "dateTime"]))
      }
    end)
  end

  defp parse_dt(iso) do
    {:ok, dt, _offset} = DateTime.from_iso8601(iso)
    DateTime.shift_zone!(dt, "Etc/UTC")
  end

  defp events_url(calendar_id),
    do: "#{@base}/calendars/#{URI.encode_www_form(calendar_id)}/events"

  defp event_url(calendar_id, event_id), do: "#{events_url(calendar_id)}/#{event_id}"

  defp req(token, opts) do
    opts
    |> Keyword.put(:auth, {:bearer, token})
    |> GoogleAuth.req()
  end
end
