# HTTPx

This is a temporary fork of [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl) of version 0.8 commit 95b8bad.
It contains a simple fix needed by the package [LiveServer.jl](https://github.com/JuliaWeb/HTTP.jl) to ensure that upon interrupting the server, all tasks are properly closed.

For more information, see [this issue](https://github.com/JuliaWeb/HTTP.jl/issues/405) and [this pull request](https://github.com/JuliaWeb/HTTP.jl/pull/406) which is applied in this package.
After chatting with Jacob Quinn, a better solution will eventually be implemented so this PR will likely not be merged in HTTP but can be used here in the mean time and allows [LiveServer.jl](https://github.com/JuliaWeb/HTTP.jl) to function properly.

To avoid this package clashing with any pre-existing installation of `HTTP.jl`, the name was changed to `HTTPx.jl`.
