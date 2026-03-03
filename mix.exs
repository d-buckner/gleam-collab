defmodule GleamCollab.MixProject do
  use Mix.Project

  def project do
    [
      app: :gleam_collab,
      version: "0.1.0",
      elixir: "~> 1.15",
      compilers: [:gleam] ++ Mix.compilers(),
      erlc_paths: erlc_paths(Mix.env()),
      erlc_include_path: "build/dev/erlang/gleam_collab/include",
      elixirc_paths: elixirc_paths(Mix.env()),
      prune_code_paths: false,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp erlc_paths(:test) do
    ["build/dev/erlang/gleam_collab/_gleam_artefacts",
     "build/dev/erlang/gleam_collab/build",
     "build/dev/erlang/gleam_collab_test/_gleam_artefacts"]
  end
  defp erlc_paths(_) do
    ["build/dev/erlang/gleam_collab/_gleam_artefacts",
     "build/dev/erlang/gleam_collab/build"]
  end

  defp aliases do
    [
      "gleam.test": [
        &write_gleam_dep_mix_exs/1,
        &compile_gleam_stdlib/1,
        fn _ -> Mix.Task.run("deps.compile") end,
        &compile_gleam_deps/1,
        &fix_dep_app_files/1,
        "compile.gleam",
        &compile_gleam_tests/1,
        "gleam.test"
      ]
    ]
  end

  # gleam_stdlib artefacts must exist before deps.compile so mix_gleam can
  # resolve stdlib types when it compiles automerge as a dep.
  defp compile_gleam_stdlib(_) do
    build_lib = Mix.Project.build_path() |> Path.join("lib")
    dep_dir = "deps/gleam_stdlib"
    out = Path.join(build_lib, "gleam_stdlib")
    artefacts = Path.join(out, "_gleam_artefacts")
    if File.dir?(dep_dir) and not File.dir?(artefacts) do
      File.mkdir_p!(out)
      0 = Mix.shell().cmd(
        "gleam compile-package --target erlang --no-beam" <>
          " --package #{dep_dir} --out #{out} --lib #{build_lib}"
      )
    end
  end

  defp compile_gleam_tests(_) do
    Mix.Tasks.Compile.Gleam.compile_package(:gleam_collab, true)
  end

  defp write_gleam_dep_mix_exs(_) do
    lock = Mix.Dep.Lock.read()
    for name <- [:gleam_stdlib, :gleam_crypto, :gleam_erlang, :gleam_http,
                 :gleam_otp, :logging, :exception, :gleam_yielder, :glisten,
                 :gramps, :mist, :gleeunit] do
      dep_dir = Path.join("deps", "#{name}")
      mix_path = Path.join(dep_dir, "mix.exs")
      if File.exists?(dep_dir) and not File.exists?(mix_path) do
        version =
          case lock[name] do
            {:hex, _, ver, _, _, _, _, _} -> ver
            _ -> "0.1.0"
          end
        module = name |> to_string() |> Macro.camelize()
        File.write!(mix_path, """
        defmodule #{module}.MixProject do
          use Mix.Project
          def project, do: [app: :#{name}, version: "#{version}"]
        end
        """)
      end
    end
  end

  defp compile_gleam_deps(_) do
    build_lib = Mix.Project.build_path() |> Path.join("lib")
    gleam_deps_in_order = [
      :gleam_stdlib,
      :automerge,
      :gleam_crypto,
      :gleam_erlang,
      :gleam_http,
      :gleam_otp,
      :logging,
      :exception,
      :gleam_yielder,
      :glisten,
      :gramps,
      :mist,
      :gleeunit,
    ]
    for name <- gleam_deps_in_order do
      dep_dir = Path.join("deps", "#{name}")
      out = Path.join(build_lib, "#{name}")
      artefacts = Path.join(out, "_gleam_artefacts")
      if File.dir?(dep_dir) and not File.dir?(artefacts) do
        File.mkdir_p!(out)
        0 = Mix.shell().cmd(
          "gleam compile-package --target erlang --no-beam" <>
            " --package #{dep_dir} --out #{out} --lib #{build_lib}"
        )
      end
    end

  end

  # Fix .app file naming issues for deps where the Hex package name differs
  # from the OTP application name.
  # hpack_erl is compiled by rebar3 as the :hpack OTP app. Mix validates that
  # the .app file application name matches the dep folder name, so we create
  # a hpack_erl.app that satisfies Mix's validation while keeping :hpack as
  # the actual application atom loaded by the VM.
  defp fix_dep_app_files(_) do
    build_lib = Mix.Project.build_path() |> Path.join("lib")
    hpack_ebin = Path.join(build_lib, "hpack_erl/ebin")
    hpack_erl_app = Path.join(hpack_ebin, "hpack_erl.app")
    hpack_app = Path.join(hpack_ebin, "hpack.app")

    if File.exists?(hpack_app) and not File.exists?(hpack_erl_app) do
      content = File.read!(hpack_app)
      # Replace the application atom name from hpack to hpack_erl so Mix
      # validation passes. The actual modules and BEAM files remain named hpack.
      rewritten = String.replace(content, "{application,hpack,", "{application,hpack_erl,", global: false)
      File.write!(hpack_erl_app, rewritten)
    end
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:mix_gleam, "~> 0.6"},
      {:gleam_stdlib, "~> 0.69"},
      {:mist, ">= 0.0.0"},
      {:gleam_otp, ">= 0.0.0"},
      {:gleam_erlang, ">= 0.0.0"},
      {:gleam_http, ">= 0.0.0"},
      {:glisten, ">= 0.0.0"},
      {:gleeunit, "~> 1.9", only: [:dev, :test]},
      {:gun, "~> 2.0", only: [:dev, :test]},
      {:automerge, "~> 0.1"},
    ]
  end
end
