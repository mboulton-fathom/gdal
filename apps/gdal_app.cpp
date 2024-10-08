#include <cmath>
#include <iostream>
#include <cstdio>
#include <fmt/core.h>
#include <unistd.h>
#include "tools/cpp/runfiles/runfiles.h"

using bazel::tools::cpp::runfiles::Runfiles;

int main(int argc, char **argv)
{
    std::string error;
    std::unique_ptr<Runfiles> runfiles(Runfiles::Create(argv[0], &error));

    if (runfiles == nullptr)
    {
        throw std::runtime_error("");
    }

    if (argc < 2)
    {
        throw std::runtime_error("not enough args");
    }

    auto binary_path = runfiles->Rlocation(argv[1]);
    printf("binary path resolved to %s\n", binary_path.c_str());

    std::string gdal_data_path = runfiles->Rlocation("_main/gcore/data");
    printf("path to gdal data: %s\n", gdal_data_path.c_str());

    std::string proj_data_path = runfiles->Rlocation("proj+/data");
    printf("path to proj data: %s\n", proj_data_path.c_str());

    std::vector<char *const> next_argv{};

    for (size_t i = 1; i < argc; i++)
    {
        next_argv.push_back(argv[i]);
    }
    next_argv.push_back(nullptr);

    std::vector<std::string> envp_strings{};
    envp_strings.push_back(fmt::format("GDAL_DATA={}", gdal_data_path));
    envp_strings.push_back(fmt::format("PROJ_DATA={}", proj_data_path));

    for (auto elem : runfiles->EnvVars())
    {
        envp_strings.push_back(fmt::format("{}={}", elem.first, elem.second));
    }

    std::vector<char *const> envp{};
    for (auto elem : envp_strings)
    {
        envp.push_back(const_cast<char *const>(elem.c_str()));
    }
    envp.push_back(nullptr);

    auto retcode = execve(argv[1], next_argv.data(), envp.data());

    return retcode;
}
