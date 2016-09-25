defmodule Hazel.Mixfile do
  use Mix.Project

  def project do
    [app: :hazel,
     version: "0.1.0",
     elixir: "~> 1.3",
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_),     do: ["lib"]

  def application() do
    [applications: [:logger, :crypto, :gproc, :ranch, :gen_stage, :gen_state_machine]]
  end

  defp deps() do
    [{:gen_stage, "~> 0.1"},
     {:bencode, "~> 0.3.2"},
     {:bit_field_set, "~> 1.2.0"},
     {:gen_state_machine, "~> 1.0.0"},
     {:gproc, "~> 0.5.0"},
     {:ranch, "~> 1.2.1"},
     {:allowance, github: "gausby/allowance"}]
  end
end
