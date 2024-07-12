load("@rules_cc//cc:defs.bzl", "cc_binary")
load("@aspect_bazel_lib//lib:paths.bzl", "to_rlocation_path", _default_location_function = "BASH_RLOCATION_FUNCTION")
load("@aspect_bazel_lib//lib:expand_template.bzl", "expand_template_rule")

BASH_RLOCATION_FUNCTION = _default_location_function + r"""
function alocation {
  local P=$1
  if [[ "${P:0:1}" == "/" ]]; then
    echo "${P}"
  else
    echo "${PWD}/${P}"
  fi
}
"""

def _wrapped_gdal_binary_impl(ctx):
    out_executable = ctx.actions.declare_file(ctx.attr.name + "_exec")

    ctx.actions.write(
        out_executable,
        BASH_RLOCATION_FUNCTION + """
        set -u -e
        export GDAL_DATA="$(alocation $(dirname $(rlocation {gdal_data})))"
        tar xf $(rlocation {proj_data})
        export PROJ_DATA=data
        $(rlocation {tool}) $@
        """.format(
            tool = to_rlocation_path(ctx, ctx.file.tool),
            gdal_data = to_rlocation_path(ctx, ctx.files._gdal_data[0]),
            proj_data = to_rlocation_path(ctx, ctx.files._proj_data[0]),
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = ctx.files.tool + ctx.files._runfiles_lib + ctx.files._gdal_data + ctx.files._proj_data)

    # propagate dependencies
    runfiles = runfiles.merge(ctx.attr._runfiles_lib[DefaultInfo].default_runfiles)

    default = DefaultInfo(
        executable = out_executable,
        runfiles = runfiles,
    )

    return [
        default,
    ]

_wrapped_gdal_binary = rule(
    implementation = _wrapped_gdal_binary_impl,
    attrs = {
        "tool": attr.label(
            doc = "gdal app file to run",
            allow_single_file = True,
            mandatory = True,
        ),
        "_gdal_data": attr.label(
            doc = "gdal data required at runtime",
            allow_files = True,
            default = "//gcore:data",
        ),
        "_proj_data": attr.label(
            doc = "proj data required at runtime",
            allow_files = True,
            default = "@proj//data",
        ),
        "_runfiles_lib": attr.label(
            allow_files = True,
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
    doc = "wrap a gdal binary and set GDAL_ENV etc. properly",
    executable = True,
)

def gdal_app(*, name, srcs, deps = [], linkopts = []):
    raw_name = "_{}".format(name)

    cc_binary(
        name = raw_name,
        linkopts = linkopts,
        srcs = srcs +
               native.glob(["*_lib.cpp"]) +
               [
                   "commonutils.cpp",
                   "nearblack_lib_floodfill.cpp",
                   "//apps/argparse:headers",
                   "//apps:headers",
                   "//alg:headers",
                   "//frmts/gtiff:headers",
                   "//frmts/vrt:headers",
                   "//gcore:headers",
                   "//gnm:headers",
                   "//ogr:headers",
                   "//ogr/ogrsf_frmts:headers",
                   "//ogr/ogrsf_frmts/generic:headers",
                   "//ogr/ogrsf_frmts/geojson:headers",
                   "//ogr/ogrsf_frmts/geojson/libjson:headers",
                   "//ogr/ogrsf_frmts/mem:headers",
                   "//port:headers",
               ],
        copts = [
            "-Ignm",
            "-Iapps/argparse",
            "-Igcore",
            "-I$(GENDIR)/gcore",
            "-Iport",
            "-I$(GENDIR)/port",
            "-Ialg",
            "-Iogr",
            "-Iogr/ogrsf_frmts",
            "-Iogr/ogrsf_frmts/mem",
            "-Iogr/ogrsf_frmts/geojson",
            "-Iogr/ogrsf_frmts/generic",
            "-Iogr/ogrsf_frmts/geojson/libjson",
            "-Ifrmts/vrt",
            "-Ifrmts/gtiff",
        ],
        defines = ["GDAL_COMPILATION"],
        deps = deps + [
            "//:gdal_core",
            "//apps:argparse",
        ],
    )

    _wrapped_gdal_binary(
        name = name,
        tool = raw_name,
    )
