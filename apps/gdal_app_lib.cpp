#include <cmath>
#include <errno.h>
#include <cstdio>
#include <fmt/core.h>
#include <iostream>
#include <ostream>
#include <unistd.h>
#include "tools/cpp/runfiles/runfiles.h"

using bazel::tools::cpp::runfiles::Runfiles;

int run_program(char *const gdal_program_name, int argc, char **argv)
{
    std::string error;
    std::unique_ptr<Runfiles> runfiles(Runfiles::Create(argv[0], &error));

    if (runfiles == nullptr)
    {
        throw std::runtime_error("");
    }

    auto bin_path = runfiles->WithSourceRepository("gdal")->Rlocation(
        fmt::format("_main/apps/_{}", gdal_program_name));
    printf("resolved to %s\n", bin_path.c_str());

    if (access(bin_path.c_str(), F_OK) == -1)
    {
        throw std::runtime_error(
            fmt::format("could not resolve {}", gdal_program_name));
    }

    std::string gdal_data_path = runfiles->Rlocation("_main/gcore/data");
    printf("path to gdal data: %s\n", gdal_data_path.c_str());

    std::string proj_data_path = runfiles->Rlocation("proj+/data");
    printf("path to proj data: %s\n", proj_data_path.c_str());

    std::vector<char *const> next_argv{};

    next_argv.push_back(gdal_program_name);
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
        // std::cout << elem <<std::endl;
        envp.push_back(const_cast<char *const>(elem.c_str()));
    }
    envp.push_back(nullptr);

    char *test_envp[] = {"A=B", 0};
    char *test_argv[] = {"/bin/sh", "-c", "env", 0};
    auto x =execve("/bin/sh", &test_argv[0], envp.data());
    if (x)
    {
        printf("%d\n", x);
        printf("%d\n", errno);
    }
    execve("/bin/sh", test_argv, test_envp);
    execve("/bin/sh", test_argv, test_envp);

    auto retcode = execve(bin_path.c_str(), next_argv.data(), envp.data());
    if (retcode)
    {
        printf("%d\n", retcode);
        printf("%d\n", errno);
    }

    return retcode;
}
