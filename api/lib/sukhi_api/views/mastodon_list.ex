# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiApi.Views.MastodonList do
  @moduledoc """
  Render a List row into Mastodon list JSON.

      %{
        id: "12",
        title: "Friends",
        replies_policy: "list" | "followed" | "none",
        exclusive: bool
      }
  """

  alias SukhiApi.Views.Id

  def render(nil), do: nil

  def render(list) do
    %{
      id: Id.encode(list.id),
      title: list.title,
      replies_policy: list.replies_policy || "list",
      exclusive: !!list.exclusive
    }
  end

  def render_list(lists) when is_list(lists), do: Enum.map(lists, &render/1)
end
