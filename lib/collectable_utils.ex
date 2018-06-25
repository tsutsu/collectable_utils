defmodule CollectableUtils do
  @doc """
  Routes an Enumerable into Collectables based on a `key_fun`.

  This function is essentially a cross between `Enum.into/2` and `Enum.group_by/2`. Rather than
  the simple lists of `Enum.group_by/2`, `into_by/3` populates a set of Collectables.

  Like `Enum.group_by/2`, the caller supplies a routing function `key_fun`, specifying a
  "bucket name" for each element to be placed into.

  Unlike `Enum.group_by/2`, when a bucket does not already exist, `initial_fun` is called with
  the new `key`, and must return a command, one of the following:

    * `{:new, Collectable.t()}` – creates a new bucket with the given Collectable as the initial value
    * `:discard` – drops the element and continues processing
    * `:invalid` – stops processing and returns an error `{:invalid, element, key}`

  For convenience, rather than an `initial_fun`, you may pass a tuple `{initial_map, not_found_command}`. Keys existing in `initial_map` will translate to `{:new, value}`. Other keys will return `not_found_command`.

  The default behavior if `initial_fun` is not passed, is to imitate the behavior of `Enum.group_by/2`. This is equivalent to passing `{%{}, {:new, []}}` as an `initial_fun`.

  ## Examples

    # imitate Enum.group_by/3 more explicitly
    iex> CollectableUtils.into_by!(
    ...>   0..5,
    ...>   fn i -> :erlang.rem(i, 3) end,
    ...>   fn _ -> {:new, []} end
    ...> )
    %{0 => [0, 3], 1 => [1, 4], 2 => [2, 5]}

    # Enum.group_by/3, but with MapSets, and for only existing keys
    iex> CollectableUtils.into_by!(
    ...>   0..5,
    ...>   fn i -> :erlang.rem(i, 3) end,
    ...>   {Map.new([0, 1], &{&1, MapSet.new()}), :discard}
    ...> )
    %{
      0 => %MapSet{map: %{0 => [], 3 => []}},
      1 => %MapSet{map: %{1 => [], 4 => []}}
    }

  ## Recipes

    # Distribute lines to files by hash
    CollectableUtils.into_by(
      event_stream,
      fn event_ln ->
        :erlang.phash2(event_ln) |> :erlang.rem(256)
      end,
      fn shard ->
        {:new, File.stream!("events-\#{shard}.events")}
      end
    )

    # Hourly log rotation
    CollectableUtils.into_by(
      log_stream,
      fn _ -> :erlang.system_time(:second) |> :erlang.div(3600) end,
      fn period -> {:new, File.stream!("app-\#{period}.log")} end
    )

  """
  def into_by(enumerable, key_fun, initial_fun \\ {%{}, {:new, []}}) do
    initial_fun =
      case initial_fun do
        f when is_function(f) ->
          f

        {initial_map, not_found_command} when is_map(initial_map) ->
          fn k -> default_initial_fun(initial_map, k, not_found_command) end
      end

    try do
      populated_collectors =
        Enum.reduce(enumerable, %{}, fn element, collectors ->
          key = key_fun.(element)

          case Map.fetch(collectors, key) do
            {:ok, {original, collector_fun}} ->
              Map.put(collectors, key, {collector_fun.(original, {:cont, element}), collector_fun})

            :error ->
              case initial_fun.(key) do
                {:new, new_collectable} ->
                  {new_original, collector_fun} = Collectable.into(new_collectable)

                  Map.put_new(
                    collectors,
                    key,
                    {collector_fun.(new_original, {:cont, element}), collector_fun}
                  )

                :discard ->
                  collectors

                :invalid ->
                  throw {:invalid, element, key}
              end
          end
        end)

      final_collectables =
        Map.new(populated_collectors, fn {name, {updated, collector_fun}} ->
          {name, collector_fun.(updated, :done)}
        end)

      {:ok, final_collectables}

    catch {:invalid, element, key} ->
      {:invalid, element, key}
    end
  end

  @doc """
  Routes an Enumerable into Collectables based on a `key_fun`, erroring out if
  if a Collectable cannot be constructed for a key.

  Like `into_by/3`, but raises an ArgumentError if `initial_fun` returns
  `:invalid`.
  """
  def into_by!(enumerable, key_fun, initial_fun \\ {%{}, {:new, []}}) do
    case into_by(enumerable, key_fun, initial_fun) do
      {:ok, final_collectables} ->
        final_collectables

      {:invalid, element, key} ->
        raise ArgumentError, "invalid key #{inspect key} derived for element: #{inspect element}"
    end
  end

  defp default_initial_fun(initial_map, key, not_found_command) do
    case Map.fetch(initial_map, key) do
      {:ok, value} -> {:new, value}
      :error -> not_found_command
    end
  end
end
