# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.OffsetPagination do
  @moduledoc """
  Offset-based pagination for admin list endpoints.

  The timeline API uses `SukhiApi.Pagination` (id-based `max_id`/`since_id`).
  Admin dashboards need jump-to-page semantics, so they pass `?page=N&per_page=M`
  and receive a `pagination` block alongside `items` in the response body.
  """

  @default_per_page 20
  @max_per_page 100

  @type opts :: %{
          page: pos_integer(),
          per_page: pos_integer(),
          offset: non_neg_integer(),
          limit: pos_integer()
        }

  @spec parse(String.t() | nil) :: opts()
  def parse(nil), do: parse("")
  def parse(""), do: to_opts(1, @default_per_page)

  def parse(query) when is_binary(query) do
    q = URI.decode_query(query)
    page = q |> Map.get("page") |> parse_int() |> clamp_page()
    per_page = q |> Map.get("per_page") |> parse_int() |> clamp_per_page()
    to_opts(page, per_page)
  end

  @spec meta(opts(), non_neg_integer()) :: map()
  def meta(%{page: page, per_page: per_page}, total) when is_integer(total) and total >= 0 do
    total_pages = if per_page > 0, do: div(total + per_page - 1, per_page), else: 0

    %{
      page: page,
      per_page: per_page,
      total: total,
      total_pages: total_pages
    }
  end

  defp to_opts(page, per_page) do
    %{
      page: page,
      per_page: per_page,
      offset: (page - 1) * per_page,
      limit: per_page
    }
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n

  defp clamp_page(nil), do: 1
  defp clamp_page(n) when n < 1, do: 1
  defp clamp_page(n), do: n

  defp clamp_per_page(nil), do: @default_per_page
  defp clamp_per_page(n) when n < 1, do: @default_per_page
  defp clamp_per_page(n) when n > @max_per_page, do: @max_per_page
  defp clamp_per_page(n), do: n
end
