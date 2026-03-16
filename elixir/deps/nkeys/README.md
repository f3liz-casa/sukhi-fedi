# Nkeys

[![hex.pm](https://img.shields.io/hexpm/v/nkeys.svg)](https://hex.pm/packages/nkeys)
[![hex.pm](https://img.shields.io/hexpm/dt/nkeys.svg)](https://hex.pm/packages/nkeys)
[![hex.pm](https://img.shields.io/hexpm/l/nkeys.svg)](https://hex.pm/packages/nkeys)
[![github.com](https://img.shields.io/github/last-commit/nats-io/nkeys.ex.svg)](https://github.com/nats-io/nkeys.ex)


Nkeys is an Elixir port of the original [Go](https://github.com/nats-io/nkeys) library. This library allows for the encoding and decoding of NATS keys
in their human-friendly, double-clickable string format. Additionally, this library supports `Xkeys` encryption and 
decryption.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `nkeys` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nkeys, "~> 0.3.0"}
  ]
end
```

