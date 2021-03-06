# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
    Pkg2

The `Pkg` module provides package management for Julia.
Use
`Pkg2.status()` for a list of installed packages,
`Pkg2.add("<pkg name>")` to add a package,
`Pkg2.update()` to update the installed packages.

Please see the manual section on packages for more information.
"""
module Pkg2

export Dir, Types, Reqs, Cache, Read, Query, Resolve, Write, Entry
export dir, init, rm, add, available, installed, status, clone, checkout,
       update, resolve, test, build, free, pin, PkgError, setprotocol!

import ..Mirrors
import ..Mirrors: metadata_url

const META_BRANCH = "metadata-v2"

mutable struct PkgError <: Exception
    msg::AbstractString
    ex::Nullable{Exception}
end
PkgError(msg::AbstractString) = PkgError(msg, Nullable{Exception}())
function Base.showerror(io::IO, pkgerr::PkgError)
    print(io, pkgerr.msg)
    if !isnull(pkgerr.ex)
        pkgex = get(pkgerr.ex)
        if isa(pkgex, CompositeException)
            for cex in pkgex
                print(io, "\n=> ")
                showerror(io, cex)
            end
        else
            print(io, "\n")
            showerror(io, pkgex)
        end
    end
end

include("PlatformEngines.jl")

for file in split("dir types reqs read query resolve write entry")
    include("$file.jl")
end
const cd = Dir.cd

dir(path...) = Dir.path(path...)

# remove extension .jl
const PKGEXT = ".jl"
splitjl(pkg::AbstractString) = endswith(pkg, PKGEXT) ? pkg[1:(end-length(PKGEXT))] : pkg

"""
    dir() -> AbstractString

Returns the absolute path of the package directory. This defaults to
`joinpath(homedir(),".julia","v\$(VERSION.major).\$(VERSION.minor)")` on all platforms (i.e.
`~/.julia/v$(VERSION.major).$(VERSION.minor)` in UNIX shell syntax). If the `JULIA_PKGDIR`
environment variable is set, then that path is used in the returned value as
`joinpath(ENV["JULIA_PKGDIR"],"v\$(VERSION.major).\$(VERSION.minor)")`. If `JULIA_PKGDIR` is
a relative path, it is interpreted relative to whatever the current working directory is.
"""
dir()

"""
    dir(names...) -> AbstractString

Equivalent to `normpath(Pkg2.dir(),names...)` – i.e. it appends path components to the
package directory and normalizes the resulting path. In particular, `Pkg2.dir(pkg)` returns
the path to the package `pkg`.
"""
dir(names...)

"""
    init(meta::AbstractString=metadata_url(), branch::AbstractString=META_BRANCH)

Initialize `Pkg2.dir()` as a package directory. This will be done automatically when the
`JULIA_PKGDIR` is not set and `Pkg2.dir()` uses its default value. As part of this process,
clones a local METADATA git repository from the site and branch specified by its arguments,
which are typically not provided. Explicit (non-default) arguments can be used to support a
custom METADATA setup.
"""
init(meta::AbstractString=metadata_url(), branch::AbstractString=META_BRANCH) = Dir.init(meta,branch)

function __init__()
    isdir(Mirrors.CACHEPATH, "versions") || mkpath(joinpath(Mirrors.CACHEPATH, "versions"))
    vers = "v$(VERSION.major).$(VERSION.minor)"
    vers = ccall(:jl_uses_cpuid_tag, Cint, ()) == 0 ? vers :
        joinpath(vers,hex(ccall(:jl_cpuid_tag, UInt64, ()), 2*sizeof(UInt64)))
    unshift!(Base.LOAD_CACHE_PATH, abspath(Dir._pkgroot(), "lib", vers))
end

"""
    edit()

Opens `Pkg2.dir("REQUIRE")` in the editor specified by the `VISUAL` or `EDITOR` environment
variables; when the editor command returns, it runs `Pkg2.resolve()` to determine and install
a new optimal set of installed package versions.
"""
edit() = cd(Entry.edit)

"""
    rm(pkg)

Remove all requirement entries for `pkg` from `Pkg2.dir("REQUIRE")` and call `Pkg2.resolve()`.
"""
rm(pkg::AbstractString) = cd(Entry.rm,splitjl(pkg))

"""
    add(pkg, vers...)

Add a requirement entry for `pkg` to `Pkg2.dir("REQUIRE")` and call `Pkg2.resolve()`. If
`vers` are given, they must be `VersionNumber` objects and they specify acceptable version
intervals for `pkg`.
"""
add(pkg::AbstractString, vers::VersionNumber...) = cd(Entry.add,splitjl(pkg),vers...)

"""
    available() -> Vector{String}

Returns the names of available packages.
"""
available() = cd(Entry.available)

"""
    available(pkg) -> Vector{VersionNumber}

Returns the version numbers available for package `pkg`.
"""
available(pkg::AbstractString) = cd(Entry.available,splitjl(pkg))

"""
    installed() -> Dict{String,VersionNumber}

Returns a dictionary mapping installed package names to the installed version number of each
package.
"""
installed() = cd(Entry.installed)

"""
    installed(pkg) -> Void | VersionNumber

If `pkg` is installed, return the installed version number. If `pkg` is registered,
but not installed, return `nothing`.
"""
installed(pkg::AbstractString) = cd(Entry.installed,splitjl(pkg))

"""
    status()

Prints out a summary of what packages are installed and what version and state they're in.
"""
status(io::IO=STDOUT) = cd(Entry.status,io)

"""
    status(pkg)

Prints out a summary of what version and state `pkg`, specifically, is in.
"""
status(pkg::AbstractString, io::IO=STDOUT) = cd(Entry.status,io,splitjl(pkg))

"""
    checkout(pkg, [branch="master"]; merge=true, pull=true)

Checkout the `Pkg2.dir(pkg)` repo to the branch `branch`. Defaults to checking out the
"master" branch. To go back to using the newest compatible released version, use
`Pkg2.free(pkg)`. Changes are merged (fast-forward only) if the keyword argument `merge ==
true`, and the latest version is pulled from the upstream repo if `pull == true`.
"""
checkout(pkg::AbstractString, branch::AbstractString="master"; merge::Bool=true, pull::Bool=true) =
    cd(Entry.checkout,splitjl(pkg),branch,merge,pull)

"""
    free(pkg)

Free the package `pkg` to be managed by the package manager again. It calls `Pkg2.resolve()`
to determine optimal package versions after. This is an inverse for both `Pkg2.checkout` and
`Pkg2.pin`.

You can also supply an iterable collection of package names, e.g., `Pkg2.free(("Pkg1",
"Pkg2"))` to free multiple packages at once.
"""
free(pkg) = cd(Entry.free,splitjl.(pkg))

"""
    pin(pkg)

Pin `pkg` at the current version. To go back to using the newest compatible released
version, use `Pkg2.free(pkg)`
"""
pin(pkg::AbstractString) = cd(Entry.pin,splitjl(pkg))

"""
    pin(pkg, version)

Pin `pkg` at registered version `version`.
"""
pin(pkg::AbstractString, ver::VersionNumber) = cd(Entry.pin,splitjl(pkg),ver)

"""
    update(pkgs...)

Update the metadata repo – kept in `Pkg2.dir("METADATA")` – then update any fixed packages
that can safely be pulled from their origin; then call `Pkg2.resolve()` to determine a new
optimal set of packages versions.

Without arguments, updates all installed packages. When one or more package names are provided as
arguments, only those packages and their dependencies are updated.
"""
update(upkgs::AbstractString...) = cd(Entry.update,Dir.getmetabranch(),Set{String}(splitjl.([upkgs...])))

"""
    resolve()

Determines an optimal, consistent set of package versions to install or upgrade to. The
optimal set of package versions is based on the contents of `Pkg2.dir("REQUIRE")` and the
state of installed packages in `Pkg2.dir()`, Packages that are no longer required are moved
into `Pkg2.dir(".trash")`.
"""
resolve() = cd(Entry.resolve)

"""
    build()

Run the build scripts for all installed packages in depth-first recursive order.
"""
build() = cd(Entry.build)

"""
    build(pkgs...)

Run the build script in `deps/build.jl` for each package in `pkgs` and all of their
dependencies in depth-first recursive order. This is called automatically by `Pkg2.resolve()`
on all installed or updated packages.
"""
build(pkgs::AbstractString...) = cd(Entry.build,[splitjl.(pkgs)...])

"""
    test(; coverage=false)

Run the tests for all installed packages ensuring that each package's test dependencies are
installed for the duration of the test. A package is tested by running its
`test/runtests.jl` file and test dependencies are specified in `test/REQUIRE`.
Coverage statistics for the packages may be generated by passing `coverage=true`.
The default behavior is not to run coverage.
"""
test(;coverage::Bool=false) = cd(Entry.test; coverage=coverage)

"""
    test(pkgs...; coverage=false)

Run the tests for each package in `pkgs` ensuring that each package's test dependencies are
installed for the duration of the test. A package is tested by running its
`test/runtests.jl` file and test dependencies are specified in `test/REQUIRE`.
Coverage statistics for the packages may be generated by passing `coverage=true`.
The default behavior is not to run coverage.
"""
test(pkgs::AbstractString...; coverage::Bool=false) = cd(Entry.test,AbstractString[splitjl.(pkgs)...]; coverage=coverage)

"""
    dependents(pkg)

List the packages that have `pkg` as a dependency.
"""
dependents(pkg::AbstractString) = Reqs.dependents(splitjl(pkg))

end # module
