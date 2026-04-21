# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Pagination do
  @moduledoc """
  Mastodon-style pagination helpers.

  Mastodon uses `?max_id=`, `?since_id=`, `?min_id=`, `?limit=` and
  publishes prev/next pages via the `Link:` HTTP header. Clients are
  expected to follow that header rather than constructing URLs.

  Used by capabilities to convert raw query strings into a normalised
  opts map (passed to gateway context functions like
  `SukhiFedi.Notes.list_statuses_for_account/2`) and to build the
  `Link:` header from a returned page of items.
  """

  @default_limit 20
  @max_limit 40

  @type opts :: %{
          optional(:max_id) => integer() | nil,
          optional(:since_id) => integer() | nil,
          optional(:min_id) => integer() | nil,
          optional(:limit) => pos_integer()
        }

  @doc """
  Parse a query string into a normalised opts map. Unknown keys are
  ignored. `limit` is clamped to `[1, #{@max_limit}]` (default
  #{@default_limit}).
  """
  @spec parse_opts(String.t() | nil) :: opts()
  def parse_opts(nil), do: %{limit: @default_limit}
  def parse_opts(""), do: %{limit: @default_limit}

  def parse_opts(query_string) when is_binary(query_string) do
    q = URI.decode_query(query_string)

    %{
      max_id: parse_int(q["max_id"]),
      since_id: parse_int(q["since_id"]),
      min_id: parse_int(q["min_id"]),
      limit: clamp_limit(parse_int(q["limit"]))
    }
  end

  @doc """
  Build a Mastodon-style `Link:` header for a page of items.

  `id_fn` extracts the id from each item (defaults to `& &1.id`); the
  newest page gives `rel="prev"` (`min_id=<first_id>`), the oldest
  page gives `rel="next"` (`max_id=<last_id>`).

  Returns the header tuple `{"link", "<url>; rel=\"...\""}`, ready to
  be appended to a response's `headers` list. Returns `nil` when the
  page is empty (no link header to set).
  """
  @spec link_header(String.t(), [term()], (term() -> integer()), opts()) ::
          {String.t(), String.t()} | nil
  def link_header(base_url, items, id_fn \\ & &1.id, opts \\ %{})
  def link_header(_base_url, [], _id_fn, _opts), do: nil

  def link_header(base_url, items, id_fn, opts) do
    first_id = id_fn.(List.first(items))
    last_id = id_fn.(List.last(items))
    limit = Map.get(opts, :limit, @default_limit)

    next_url = "#{base_url}?#{URI.encode_query(%{"max_id" => last_id, "limit" => limit})}"
    prev_url = "#{base_url}?#{URI.encode_query(%{"min_id" => first_id, "limit" => limit})}"

    {"link", ~s(<#{next_url}>; rel="next", <#{prev_url}>; rel="prev")}
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n

  defp clamp_limit(nil), do: @default_limit
  defp clamp_limit(n) when n < 1, do: @default_limit
  defp clamp_limit(n) when n > @max_limit, do: @max_limit
  defp clamp_limit(n), do: n
end
