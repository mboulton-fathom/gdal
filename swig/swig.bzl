## https://github.com/tensorflow/tensorflow/blob/v0.6.0/tensorflow/tensorflow.bzl

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:paths.bzl", "paths")

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

gen_swig_python = rule(
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
