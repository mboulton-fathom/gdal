package main

import (
    "errors"
    "fmt"
    "os"
    "os/exec"

    "github.com/bazelbuild/rules_go/go/runfiles"
)

var WrappedBinary string

func main() {
    err := run()
    if err != nil {
        panic(err)
    }
}

func run() error {
    if WrappedBinary == "" {
        return errors.New("no WrappedBinary defined")
    }

    r, err := runfiles.New()
    if err != nil {
        return fmt.Errorf("runfiles.New(): %w", err)
    }

    binPath, err := r.Rlocation(fmt.Sprintf("gdal+/apps/%s", WrappedBinary))
    if err != nil {
        return fmt.Errorf("%T.WithSourceRepo(): %w", r, err)
    }

    cmd := exec.Command(binPath, os.Args[1:]...)
    cmd.Env = append(cmd.Env, r.Env()...)
    gdalData, err := r.Rlocation("gcore/data")
    cmd.Env = append(cmd.Env, fmt.Sprintf("GDAL_DATA=%s", gdalData))
    projData, err := r.Rlocation("proj+/data")
    cmd.Env = append(cmd.Env, fmt.Sprintf("PROJ_DATA=%s", projData))

    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    cmd.Stdin = os.Stdin

    return cmd.Run()
}
