defmodule Hazel.Mixfile do
  use Mix.Project

  def project do
    [app: :hazel,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application() do
    [applications: [:logger, :gproc, :gen_stage]]
  end

  defp deps() do
    [{:gen_stage, "~> 0.1"},
     {:bencode, "~> 0.3.2"},
     {:bit_field_set, "~> 0.1.0"},
     {:gen_fsm, "~> 0.1.0"},
     {:gproc, "~> 0.5.0"}]
  end
end
