package main

import (
    "archive/tar"
    "errors"
    "fmt"
    "io"
    "os"
    "os/exec"
    "path/filepath"

    "github.com/bazelbuild/rules_go/go/runfiles"
    "github.com/bazelbuild/rules_go/go/tools/bazel"
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
        return fmt.Errorf("%T.Rlocation(): %w", r, err)
    }

    cmd := exec.Command(binPath, os.Args[1:]...)
    cmd.Env = append(cmd.Env, r.Env()...)
    gdalData, err := r.Rlocation("gdal+/gcore/data")
    if !exists(gdalData) {
        return fmt.Errorf("couldn't locate gdal data at %s", gdalData)
    }
    cmd.Env = append(cmd.Env, fmt.Sprintf("GDAL_DATA=%s", gdalData))

    projDataTar, err := r.Rlocation("proj/data/data.tar")
    if !exists(gdalData) {
        return fmt.Errorf("couldn't locate proj data at %s", projDataTar)
    }
    projTmp, err := os.MkdirTemp(bazel.TestTmpDir(), "")
    if err != nil {
        return fmt.Errorf("os.MkdirTemp(): %w", err)
    }
    defer os.RemoveAll(projTmp)

    reader, err := os.Open(projDataTar)
    if err != nil {
        return fmt.Errorf("os.Open(): %w", err)
    }

    tarReader := tar.NewReader(reader)
    for {
        header, err := tarReader.Next()
        if err != nil {
            if err == io.EOF {
                break
            }
            return fmt.Errorf("%T.Next(): %w", tarReader, err)
        }

        switch header.Typeflag {
        case tar.TypeDir:
            if err := os.Mkdir(filepath.Join(projTmp, header.Name), 0744); err != nil {
                return fmt.Errorf("os.Mkdir(): %w", err)
            }

        case tar.TypeReg:
            outFile, err := os.Create(filepath.Join(projTmp, header.Name))
            if err != nil {
                return fmt.Errorf("os.Create(): %w", err)
            }
            if _, err := io.Copy(outFile, tarReader); err != nil {
                return fmt.Errorf("io.Copy(): %w", err)
            }
            _ = outFile.Close()

        default:
            return fmt.Errorf("unknown type: %v in %s", header.Typeflag, header.Name)
        }
    }

    cmd.Env = append(cmd.Env, fmt.Sprintf("PROJ_DATA=%s", filepath.Join(projTmp, "data")))

    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    cmd.Stdin = os.Stdin

    return cmd.Run()
}

func exists(path string) bool {
    if _, err := os.Stat(path); err != nil {
        return false
    }
    return true
}
