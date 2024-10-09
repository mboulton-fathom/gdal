## https://github.com/tensorflow/tensorflow/blob/v0.6.0/tensorflow/tensorflow.bzl

load("@bazel_skylib//lib:sets.bzl", "sets")

# Bazel rules for building swig files.
def gen_swig_python_impl(ctx):
    if len(ctx.files.srcs) != 1:
        fail("Exactly one SWIG source file label must be specified.", "srcs")

    module_name = ctx.attr.module_name
    cc_out = ctx.actions.declare_directory(ctx.attr.name + ".cout")
    py_out = ctx.actions.declare_directory(ctx.attr.name + ".pyout")
    args = ["-c++", "-python"]
    args += ["-module", module_name]
    args += ["-l" + f.path for f in ctx.files.swig_includes]
    cc_include_dirs = sets.make()
    cc_includes = sets.make()
    for dep in ctx.attr.deps:
        cc_include_dirs = sets.union(cc_include_dirs, sets.make([h.dirname for h in dep[CcInfo].compilation_context.headers.to_list()]))
        cc_includes = sets.union(cc_includes, sets.make(dep[CcInfo].compilation_context.headers.to_list()))
    args += ["-I" + x for x in sets.to_list(cc_include_dirs)]
    args += ["-o", cc_out.path]
    args += ["-outdir", py_out.dirname]
    args += [src.path for src in ctx.files.srcs]
    outputs = [cc_out, py_out]
    ctx.actions.run(
        executable = ctx.executable.swig_binary,
        arguments = args,
        mnemonic = "PythonSwig",
        inputs = ctx.files.srcs +
                 sets.to_list(cc_includes) +
                 ctx.files.swig_includes +
                 ctx.files.swig_deps,
        outputs = outputs,
        progress_message = "SWIGing",
    )
    return [
        DefaultInfo(files = depset(direct = outputs)),
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
        "deps": attr.label_list(
            allow_files = True,
            providers = [CcInfo],
        ),
        "swig_deps": attr.label_list(
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
