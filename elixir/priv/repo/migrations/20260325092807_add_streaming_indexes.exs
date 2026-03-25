defmodule SukhiFedi.Repo.Migrations.AddStreamingIndexes do
  use Ecto.Migration

  def change do
    # Optimize feed queries
    create_if_not_exists index(:objects, [:created_at, :type])
    create_if_not_exists index(:objects, [:actor_id, :created_at])
    
    # Optimize follower lookups
    create_if_not_exists index(:follows, [:followee_id, :state])
    create_if_not_exists index(:follows, [:follower_uri, :state])
  end
end
