defmodule Equivalex do
  import Bitwise

  @moduledoc """
  polymorphic constant time comparisons

  Compare arbitrary structures, using constant time comparisons
  where possible.  This might allow for checking of multiple strings
  in a "secure" (constant time) way, without leaking timing information.

  """

  @doc """
  determine if two structures are the same

  Comprisons are done bitwise on the destructured data.

  The only short-circuits are for structures of differing sizes.  Thus,
  information about whether a suspect string is of the correct length
  may be leaked.
  """
  @spec equal?(term, term) :: boolean
  def equal?(a, b), do: differing_elements(a, b, 0) == 0

  defp differing_elements(a, b, _c) when is_map(a) and is_map(b) do
    differing_elements(a |> Map.to_list() |> Enum.sort(), b |> Map.to_list() |> Enum.sort(), 0)
  end

  defp differing_elements(a, b, _c) when is_tuple(a) and is_tuple(b) do
    differing_elements(Tuple.to_list(a), Tuple.to_list(b), 0)
  end

  defp differing_elements([], [], c), do: c

  defp differing_elements([a | ra], [b | rb], c),
    do: differing_elements(ra, rb, c ||| comparison(a, b))

  defp differing_elements(<<>>, <<>>, c), do: c

  defp differing_elements(<<a::size(1), ra::bitstring>>, <<b::size(1), rb::bitstring>>, c) do
    differing_elements(ra, rb, c ||| comparison(a, b))
  end

  defp differing_elements(_a, _b, _c), do: 1

  defp comparison(a, b)
       when (is_list(a) and is_list(b)) or (is_tuple(a) and is_tuple(b)) or
              (is_map(a) and is_map(b)) or (is_binary(a) and is_binary(b)),
       do: differing_elements(a, b, 0)

  defp comparison(a, b), do: if(a == b, do: 0, else: 1)
end
