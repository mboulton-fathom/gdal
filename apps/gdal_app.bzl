load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")
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

    ctx.actions.symlink(output = out_executable, target_file = ctx.file._wrapper)

    runfiles = ctx.runfiles(files = ctx.files.tool + ctx.files._gdal_data + ctx.files._proj_data)

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
        "_wrapper": attr.label(
            allow_single_file = True,
            cfg = "exec",
            default = "//apps:app_wrapper",
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
        srcs = srcs,
        defines = ["GDAL_COMPILATION"],
        deps = deps + [
            "//apps",
        ],
        visibility = ["//visibility:private"],
    )

    cc_binary(
        name = name,
        srcs = [":gdal_app.cpp"],
        data = [
            "//gcore:data",
            "@proj//data",
            raw_name,
        ],
        defines = [
            'GDAL_PROGRAM_NAME=\\"{}\\"'.format(name),
        ],
        deps = [
            ":app_wrapper_lib",
        ],
        visibility = ["//visibility:public"],
    )

#
#    _wrapped_gdal_binary(
#        name = name,
#        tool = raw_name,
#        visibility = ["//visibility:public"],
#    )
