load("@rules_cc//cc:defs.bzl", "cc_binary")

def gdal_app(*, name, srcs, deps = [], linkopts = []):
    cc_binary(
        name = name,
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
