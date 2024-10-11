## https://github.com/tensorflow/tensorflow/blob/v0.6.0/tensorflow/tensorflow.bzl

load("@aspect_bazel_lib//lib:copy_file.bzl", "copy_file")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@aspect_bazel_lib//lib:copy_directory.bzl", "copy_directory_bin_action")
load("@rules_cc//cc:defs.bzl", "cc_library", "cc_shared_library")

def _extract_numpy_headers_impl(ctx):
    """extracts numpy wheel and gets the headers"""

    extracted = ctx.actions.declare_directory(ctx.attr.name + ".extracted")
    ctx.actions.run(
        executable = "unzip",
        inputs = [ctx.file.numpy],
        outputs = [extracted],
        arguments = ["-q", ctx.file.numpy.path, "-d", extracted.path],
        mnemonic = "unzip",
    )

    # We only care about the headers, so copy them into their own directory
    out_folder = ctx.actions.declare_directory(ctx.attr.name + ".numpy")
    copy_directory_bin = ctx.toolchains["@aspect_bazel_lib//lib:copy_directory_toolchain_type"].copy_directory_info.bin

    args = [
        extracted.path + "/numpy/core/include",
        out_folder.path,
    ]

    ctx.actions.run(
        inputs = [extracted],
        outputs = [out_folder],
        executable = copy_directory_bin,
        arguments = args,
        mnemonic = "CopyDirectory",
        progress_message = "Copying directory",
    )

    return [
        DefaultInfo(files = depset(direct = [out_folder])),
    ]

_extract_numpy_headers = rule(
    attrs = {
        "numpy": attr.label(
            default = "@gdal_python_deps//numpy:whl",
            allow_single_file = True,
            doc = "numpy wheel to use to build gdal_array.i. Defaults to 1.26.4",
        ),
    },
    doc = "extracts the given numpy wheel and copies the header directory into a top-level directory",
    implementation = _extract_numpy_headers_impl,
    toolchains = ["@aspect_bazel_lib//lib:copy_directory_toolchain_type"],
)

# Bazel rules for building swig files.
def gen_swig_python_impl(ctx):
    module_name = ctx.attr.module_name

    # An initial c++ template file is created for swig, which is then modified further down
    cc_out_tmp = ctx.actions.declare_file(ctx.attr.name + ".cpp.tmpl")
    py_out = ctx.actions.declare_file(ctx.attr.name + ".py")
    args = ["-c++", "-python"]
    args += ["-module", module_name]

    includes_folders = sets.to_list(sets.make([paths.dirname(f.path) for f in ctx.files.swig_includes + ctx.files._swig_deps]))

    # Reverse them because we want the specific python ones ot be included first
    includes_folders = includes_folders[::-1]
    args += ["-I" + d for d in includes_folders]

    # Add any C header deps
    cc_include_dirs = []
    cc_includes = []
    for dep in ctx.attr.cdeps:
        cc_include_dirs += [h.dirname for h in dep[CcInfo].compilation_context.headers.to_list()]
        cc_includes += dep[CcInfo].compilation_context.headers.to_list()

    # deduplicate
    cc_include_dirs = sets.to_list(sets.make(cc_include_dirs))
    cc_includes = sets.to_list(sets.make(cc_includes))

    args += ["-I" + x for x in cc_include_dirs]
    args += ["-o", cc_out_tmp.path]
    args += ["-outdir", py_out.dirname]
    args += [ctx.file.src.path]

    ctx.actions.run(
        executable = ctx.executable.swig_binary,
        arguments = args,
        mnemonic = "PythonSwig",
        inputs = ctx.files.src +
                 cc_includes +
                 ctx.files.swig_includes +
                 ctx.files._swig_deps,
        outputs = [cc_out_tmp, py_out],
        progress_message = "SWIGing",
    )

    cc_out = ctx.actions.declare_file(ctx.attr.name + ".cpp")
    ctx.actions.expand_template(
        template = cc_out_tmp,
        output = cc_out,
        # See swig/python/modify_cpp_files.cmake
        substitutions = {
            "PyObject *resultobj = 0;": "PyObject *resultobj = 0; int bLocalUseExceptionsCode = GetUseExceptions();",
        },
    )

    return [
        DefaultInfo(files = depset(direct = [cc_out, py_out])),
    ]

_gen_swig_python = rule(
    attrs = {
        "src": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "swig_includes": attr.label_list(
            allow_files = True,
        ),
        "cdeps": attr.label_list(
            allow_files = True,
            providers = [CcInfo],
        ),
        "_swig_deps": attr.label_list(
            default = [
                "@swig//:lib_python",
            ],
        ),
        "numpy": attr.label(
            default = "@gdal_python_deps//numpy:whl",
            allow_single_file = True,
            doc = "numpy wheel to use to build gdal_array.i. Defaults to 1.26.4",
        ),
        "module_name": attr.string(mandatory = True),
        "py_module_name": attr.string(mandatory = True),
        "swig_binary": attr.label(
            default = "@swig//:swig",
            cfg = "exec",
            executable = True,
            allow_files = True,
        ),
    },
    doc = "Swigs the given .i file in src into a .py and .cpp file",
    implementation = gen_swig_python_impl,
)

def swig_python_bindings(*, module_names):
    """Generate swig bindings for each GDAL module"""

    _extract_numpy_headers(
        name = "numpy_headers",
    )

    for modname in module_names:
        _gen_swig_python(
            name = modname,
            src = "//swig/include:{}.i".format(modname),
            cdeps = ["//:gdal_core"],
            module_name = modname,
            py_module_name = modname,
            swig_includes = [
                "//swig/include",
                "//swig/include/python",
            ],
        )

        # Generate C swig bindings
        cc_library(
            name = "{}.so".format(modname),
            srcs = [modname],
            hdrs = [":numpy_headers"],
            copts = [
                # Allow in-tree builds
                "-I$(GENDIR)/swig/python/osgeo/numpy_headers.numpy",
                # Allow out-of-tree builds
                "-I$(GENDIR)/external/gdal+/swig/python/osgeo/numpy_headers.numpy",
            ],
            deps = [
                "//:gdal_core",
                "//apps",
                # See https://github.com/bazelbuild/rules_python/issues/824
                "@rules_python//python/cc:current_py_cc_headers",
            ],
        )

        # Rename from `lib_gdal.so` to `_gdal.so` for swig imports
        cc_shared_library(
            name = "_{}.so".format(modname),
            shared_lib_name = "_{}.so".format(modname),
            deps = ["{}.so".format(modname)],
        )
