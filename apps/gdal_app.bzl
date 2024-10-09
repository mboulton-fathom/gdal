load("@rules_cc//cc:defs.bzl", "cc_binary")
load("@rules_go//go:def.bzl", "go_binary")

def gdal_app(*, name, deps = [], **kwargs):
    raw_name = "_{}".format(name)

    cc_binary(
        name = raw_name,
        defines = ["GDAL_COMPILATION"],
        deps = deps + [
            "//apps",
        ],
        visibility = ["//visibility:private"],
        **kwargs
    )

    go_binary(
        name = name,
        data = [
            "//gcore:data",
            "@proj//data",
            raw_name,
        ],
        x_defs = {
            "github.com/mboulton-fathom/gdal/apps.WrappedBinary": raw_name,
        },
        srcs = [
            "app_wrapper.go",
        ],
        importpath = "github.com/mboulton-fathom/gdal/apps",
        deps = ["@rules_go//go/runfiles:go_default_library"],
    )
