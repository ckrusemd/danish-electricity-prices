#!/usr/bin/env python3
"""Offline repository syntax checks; optional PyYAML validates every YAML file."""
import pathlib
import subprocess
import sys


def main():
    root = pathlib.Path.cwd()
    try:
        import yaml
    except ImportError:
        raise RuntimeError("PyYAML is required for YAML validation") from None
    files = [p for p in root.rglob("*") if p.is_file() and not any(
        part in (".git", "renv", ".cache", "_site", "_freeze", "node_modules") for part in p.relative_to(root).parts)]
    for path in files:
        if path.suffix in (".yml", ".yaml"):
            try:
                with path.open(encoding="utf-8") as handle:
                    list(yaml.safe_load_all(handle))
            except (OSError, yaml.YAMLError):
                raise RuntimeError("Invalid repository YAML: " + str(path.relative_to(root))) from None
        elif path.suffix == ".sh":
            if subprocess.run(["bash", "-n", str(path)], capture_output=True).returncode:
                raise RuntimeError("Invalid shell syntax: " + str(path.relative_to(root)))
        elif path.suffix == ".py":
            try:
                compile(path.read_text(encoding="utf-8"), str(path), "exec")
            except (OSError, SyntaxError):
                raise RuntimeError("Invalid Python syntax: " + str(path.relative_to(root))) from None
    r = 'files <- c(list.files("R", pattern="[.]R$", recursive=TRUE, full.names=TRUE), list.files("scripts", pattern="[.]R$", recursive=TRUE, full.names=TRUE), list.files("tests", pattern="[.]R$", recursive=TRUE, full.names=TRUE)); for (file in files) tryCatch(invisible(parse(file=file)), error=function(e) stop(paste("Invalid R syntax:", file), call.=FALSE))'
    if subprocess.run(["Rscript", "--vanilla", "-e", r], capture_output=True).returncode:
        raise RuntimeError("R source/scripts/tests syntax validation failed")
    print("Repository YAML, shell, Python, and R syntax passed")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError) as error:
        print(str(error) if isinstance(error, RuntimeError) else "Repository syntax check failed", file=sys.stderr)
        sys.exit(1)
