defmodule CollectableUtils.MixProject do
  use Mix.Project

  def project, do: [
    app: :collectable_utils,
    version: "0.1.0",
    elixir: "~> 1.6",
    description: description(),
    package: package(),
    deps: deps()
  ]

  defp description, do:
  """
  A collection of functions for working with Collectables.
  """

  defp package, do: [
    name: :collectable_utils,
    files: ["config", "lib", "mix.exs", "LICENSE"],
    maintainers: ["Levi Aul"],
    licenses: ["MIT"],
    links: %{"GitHub" => "https://github.com/tsutsu/collectable_utils"}
  ]

  def application, do: [
    extra_applications: [:logger]
  ]

  defp deps, do: [
    {:ex_doc, ">= 0.0.0", only: :dev}
  ]
end
