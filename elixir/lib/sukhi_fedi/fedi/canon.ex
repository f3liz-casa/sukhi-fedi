# SPDX-License-Identifier: AGPL-3.0-or-later
defmodule SukhiFedi.Fedi.Canon do
  @moduledoc """
  JSON-LD canonicalization for LD signatures.

  A document is expanded to RDF (json_ld), canonicalized with
  URDNA2015/RDFC-1.0 (rdf.ex), serialized as sorted canonical N-Quads
  and SHA-256-hashed — the exact pipeline `jsonld.canonize` runs inside
  fedify's `signJsonLd`, so signatures stay verifiable by Mastodon-family
  receivers.

  Context documents are vendored under `priv/fedify/contexts` and served
  from memory by `ContextLoader`: signing must never depend on w3id.org
  being up (its identity/v1 redirect chain is already half-dead), and a
  fetched-at-runtime context would let a third party alter what our
  signatures mean.
  """

  @doc """
  Canonicalizes a document with JCS (RFC 8785) and returns the raw
  SHA-256 digest — the canonicalization step of the `eddsa-jcs-2022`
  cryptosuite (FEP-8b32 Object Integrity Proofs). Unlike `hash/1` this
  works on the literal JSON, no RDF expansion, so it cannot fail on
  unresolvable contexts.
  """
  @spec jcs_hash(map()) :: binary()
  def jcs_hash(document) when is_map(document) do
    :crypto.hash(:sha256, Jcs.encode(document))
  end

  @doc """
  Canonicalizes a JSON-LD document (a map) and returns the lowercase
  SHA-256 hex digest of its canonical N-Quads form.
  """
  @spec hash(map()) :: {:ok, String.t()} | {:error, term()}
  def hash(document) when is_map(document) do
    options = JSON.LD.Options.new(document_loader: __MODULE__.ContextLoader)

    canonical =
      document
      |> JSON.LD.Decoder.to_rdf(options)
      |> RDF.Dataset.canonicalize()
      |> RDF.Dataset.quads()
      # Encoder.statement/2 already yields the full `… .\n` line; sort
      # by code point and join — the canonical N-Quads form.
      |> Enum.map(&RDF.NQuads.Encoder.statement(&1, nil))
      |> Enum.sort()
      |> Enum.join()

    {:ok, Base.encode16(:crypto.hash(:sha256, canonical), case: :lower)}
  rescue
    # json_ld raises on unresolvable contexts / malformed documents.
    # Signing our own documents this never fires; surface it as data.
    error -> {:error, error}
  end

  defmodule ContextLoader do
    @moduledoc """
    Serves the vendored JSON-LD context documents; refuses the network.
    """

    @behaviour JSON.LD.DocumentLoader

    alias JSON.LD.DocumentLoader.RemoteDocument

    @context_files %{
      "https://www.w3.org/ns/activitystreams" => "activitystreams.json",
      "https://w3id.org/security/v1" => "security-v1.json",
      "https://w3id.org/identity/v1" => "identity-v1.json",
      "https://w3id.org/security/data-integrity/v1" => "security-data-integrity-v1.json",
      "https://w3id.org/security/multikey/v1" => "security-multikey-v1.json",
      "https://www.w3.org/ns/did/v1" => "did-v1.json",
      "https://gotosocial.org/ns" => "gotosocial-ns.json"
    }

    @impl true
    def load(url, _options) do
      case Map.fetch(@context_files, url) do
        {:ok, file} ->
          {:ok, %RemoteDocument{document: context!(file), document_url: url}}

        :error ->
          {:error, "context #{url} is not vendored (priv/fedify/contexts)"}
      end
    end

    # Contexts are immutable spec documents; parse each once per node.
    defp context!(file) do
      key = {__MODULE__, file}

      case :persistent_term.get(key, nil) do
        nil ->
          document =
            :sukhi_fedi
            |> Application.app_dir("priv/fedify/contexts/#{file}")
            |> File.read!()
            |> JSON.decode!()

          :persistent_term.put(key, document)
          document

        document ->
          document
      end
    end
  end
end
