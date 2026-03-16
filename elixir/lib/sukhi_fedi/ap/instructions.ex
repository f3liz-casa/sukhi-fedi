# SPDX-License-Identifier: MPL-2.0
defmodule SukhiFedi.AP.Instructions do
  @moduledoc """
  Parses and executes instructions returned by Deno workers.
  """

  alias SukhiFedi.Delivery.Worker
  alias SukhiFedi.Repo
  alias SukhiFedi.Schema.Follow
  alias SukhiFedi.Schema.Object

  @doc """
  Executes an instruction map returned from the ap.inbox NATS topic.
  """
  @spec execute(map()) :: :ok
  def execute(%{"action" => "save", "object" => object_data}) do
    insert_object(object_data)
    :ok
  end

  def execute(%{"action" => "save_and_reply", "save" => save_data, "reply" => reply, "inbox" => inbox_url}) do
    insert_follow(save_data)
    %{raw_json: reply, inbox_url: inbox_url}
    |> Worker.new()
    |> Oban.insert!()

    :ok
  end

  def execute(%{"action" => "ignore"}) do
    :ok
  end

  defp insert_object(data) do
    %Object{
      ap_id: data["id"],
      type: data["type"],
      actor_id: data["actor"],
      raw_json: data
    }
    |> Repo.insert(on_conflict: :nothing)
  end

  defp insert_follow(data) do
    account = Repo.get_by!(SukhiFedi.Schema.Account, username: data["followee_username"])

    %Follow{
      follower_uri: data["follower_uri"],
      followee_id: account.id,
      state: "accepted"
    }
    |> Repo.insert(on_conflict: :nothing)
  end
end
