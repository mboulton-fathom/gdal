## https://github.com/tensorflow/tensorflow/blob/v0.6.0/tensorflow/tensorflow.bzl

load("@aspect_bazel_lib//lib:copy_file.bzl", "copy_file")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@aspect_bazel_lib//lib:copy_directory.bzl", "copy_directory_bin_action")
load("@rules_cc//cc:defs.bzl", "cc_library")

def _extract_numpy_headers_impl(ctx):
    """extracts numpy wheel and gets the headers"""

    extracted = ctx.actions.declare_directory(ctx.attr.name + ".extracted")
    ctx.actions.run(
        executable = "unzip",
        inputs = depset(direct = [ctx.file.numpy]),
        outputs = [extracted],
        arguments = ["-q", ctx.file.numpy.path, "-d", extracted.path],
        mnemonic = "unzip",
    )

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
            default = "@python_deps//numpy:whl",
            allow_single_file = True,
            doc = "numpy wheel to use to build gdal_array.i. Defaults to 1.26.4",
        ),
    },
    implementation = _extract_numpy_headers_impl,
    toolchains = ["@aspect_bazel_lib//lib:copy_directory_toolchain_type"],
)

# Bazel rules for building swig files.
def gen_swig_python_impl(ctx):
    if len(ctx.files.srcs) != 1:
        fail("Exactly one SWIG source file label must be specified.", "srcs")

    module_name = ctx.attr.module_name

    # An initial template file is created for swig, which is then modified further down
    # See swig/python/modify_cpp_files.cmake
    cc_out_tmp = ctx.actions.declare_file(ctx.attr.name + ".cpp.tmpl")
    py_out = ctx.actions.declare_file(ctx.attr.name + ".py")
    args = ["-c++", "-python"]
    args += ["-module", module_name]

    includes_folders = sets.to_list(sets.make([paths.dirname(f.path) for f in ctx.files.swig_includes + ctx.files._swig_deps]))

    # Reverse them because we want the specific python ones ot be included first
    includes_folders = includes_folders[::-1]
    args += ["-I" + d for d in includes_folders]

    # Add any C header deps
    cc_include_dirs = sets.make()
    cc_includes = sets.make()
    for dep in ctx.attr.cdeps:
        cc_include_dirs = sets.union(cc_include_dirs, sets.make([h.dirname for h in dep[CcInfo].compilation_context.headers.to_list()]))
        cc_includes = sets.union(cc_includes, sets.make(dep[CcInfo].compilation_context.headers.to_list()))
    args += ["-I" + x for x in sets.to_list(cc_include_dirs)]

    args += ["-o", cc_out_tmp.path]
    args += ["-outdir", py_out.dirname]
    args += [src.path for src in ctx.files.srcs]

    outputs = [cc_out_tmp, py_out]
    ctx.actions.run(
        executable = ctx.executable.swig_binary,
        arguments = args,
        mnemonic = "PythonSwig",
        inputs = ctx.files.srcs +
                 sets.to_list(cc_includes) +
                 ctx.files.swig_includes +
                 ctx.files._swig_deps,
        outputs = outputs,
        progress_message = "SWIGing",
    )

    cc_out = ctx.actions.declare_file(ctx.attr.name + ".cpp")
    ctx.actions.expand_template(
        template = cc_out_tmp,
        output = cc_out,
        substitutions = {
            "PyObject *resultobj = 0;": "PyObject *resultobj = 0; int bLocalUseExceptionsCode = GetUseExceptions();",
        },
    )

    return [
        DefaultInfo(files = depset(direct = [cc_out, py_out])),
    ]

_gen_swig_python = rule(
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
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
            default = "@python_deps//numpy:whl",
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
    implementation = gen_swig_python_impl,
)

def swig_python_bindings(*, module_names):
    _extract_numpy_headers(
        name = "numpy_headers",
    )

    for modname in module_names:
        _gen_swig_python(
            name = modname,
            srcs = [
                "//swig/include:{}.i".format(modname),
            ],
            cdeps = ["//:gdal_core"],
            module_name = modname,
            py_module_name = modname,
            swig_includes = [
                "//swig/include",
                "//swig/include/python:includes",
            ],
        )

        cc_library(
            name = "_{}_lib".format(modname),
            srcs = [modname],
            hdrs = [":numpy_headers"],
            copts = ["-I$(GENDIR)/swig/python/osgeo/numpy_headers.numpy"],
            deps = [
                "//:gdal_core",
                "//apps",
                # See https://github.com/bazelbuild/rules_python/issues/824
                "@rules_python//python/cc:current_py_cc_headers",
            ],
        )

        native.cc_shared_library(
            name = "_{}".format(modname),
            shared_lib_name = "_{}.so".format(modname),
            deps = ["_{}_lib".format(modname)],
        )
