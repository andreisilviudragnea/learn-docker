# Docker multi-stage builds

## Context

This is a feature which allows using Dockerfiles like Makefiles. More details can be found
[here](https://docs.docker.com/develop/develop-images/multistage-build/).

Let's take this example:

```Dockerfile
FROM ubuntu AS base
RUN echo "base"

FROM base AS step1
RUN echo "step1"

FROM base AS step2
RUN echo "step2"
```

Conceptually, the above Dockerfile is equivalent to this Makefile:

```Makefile
base:
	echo "base"

step1: base
	echo "step1"

step2: base
	echo "step2"
```

Let's suppose we want to run `step2`, which depends on `base`. The build should skip
building `step1`:

- Docker: `docker build --no-cache -f Dockerfile --target step2 .`
    - `--no-cache` disables Docker build cache, so the example can be better undestood by re-running it
      multiple times
    - `-f Dockerfile` is redundant in this case, but it is specified for understanding exactly which `Dockerfile` is
      executed
    - `--target step2` specifies which step to build

Output:
```console
[+] Building 0.4s (7/7) FINISHED                                                                                                                                                                                
 => [internal] load build definition from Dockerfile                                                                                                                                                       0.0s
 => => transferring dockerfile: 36B                                                                                                                                                                        0.0s
 => [internal] load .dockerignore                                                                                                                                                                          0.0s
 => => transferring context: 2B                                                                                                                                                                            0.0s
 => [internal] load metadata for docker.io/library/ubuntu:latest                                                                                                                                           0.0s
 => CACHED [base 1/2] FROM docker.io/library/ubuntu                                                                                                                                                        0.0s
 => [base 2/2] RUN echo "base"                                                                                                                                                                             0.1s
 => [step2 1/1] RUN echo "step2"                                                                                                                                                                           0.2s
 => exporting to image                                                                                                                                                                                     0.0s
 => => exporting layers                                                                                                                                                                                    0.0s
 => => writing image sha256:75f86eb8e68bbb50ea2ae1734face750e27c154ec3947696515bfcc90a0774a1                                                                                                               0.0s
```

- Make: `make step2`

Output:
```console
echo "base"
base
echo "step2"
step2
```

## BuildKit backend

Since version 18.09, Docker build integrated [BuildKit](https://docs.docker.com/develop/develop-images/build_enhancements/)
which makes the build process more efficient. It also fixes a bug in Multi-stage builds present in the legacy
Docker build engine configuration.

However, this bug cannot be detected on MacOS, since BuildKit is enabled by default.
On Linux, BuildKit is **NOT** enabled by default.

Enabling BuildKit build can be done by setting the `DOCKER_BUILDKIT=1` environment variable.

- `DOCKER_BUILDKIT=1`: Running `DOCKER_BUILDKIT=1 docker build --no-cache -f Dockerfile --target step2 .` produces the
  same result as above:

```console
[+] Building 0.4s (7/7) FINISHED                                                                                                                                                                                
 => [internal] load build definition from Dockerfile                                                                                                                                                       0.0s
 => => transferring dockerfile: 36B                                                                                                                                                                        0.0s
 => [internal] load .dockerignore                                                                                                                                                                          0.0s
 => => transferring context: 2B                                                                                                                                                                            0.0s
 => [internal] load metadata for docker.io/library/ubuntu:latest                                                                                                                                           0.0s
 => CACHED [base 1/2] FROM docker.io/library/ubuntu                                                                                                                                                        0.0s
 => [base 2/2] RUN echo "base"                                                                                                                                                                             0.1s
 => [step2 1/1] RUN echo "step2"                                                                                                                                                                           0.2s
 => exporting to image                                                                                                                                                                                     0.0s
 => => exporting layers                                                                                                                                                                                    0.0s
 => => writing image sha256:4a4e22dc4e8bb1f9cfcbdc88f1ac699e5542a653803066ec812c19e5dac811d7                                                                                                               0.0s
```

- `DOCKER_BUILDKIT=0`: Running `DOCKER_BUILDKIT=0 docker build --no-cache -f Dockerfile --target step2 .` produces a
  surprising result:

```console
Sending build context to Docker daemon  178.7kB
Step 1/6 : FROM ubuntu AS base
 ---> a7870fd478f4
Step 2/6 : RUN echo "base"
 ---> Running in 26de818035ee
base
Removing intermediate container 26de818035ee
 ---> 0f81232dc95d
Step 3/6 : FROM base AS step1
 ---> 0f81232dc95d
Step 4/6 : RUN echo "step1"
 ---> Running in 40e2c649b4d4
step1
Removing intermediate container 40e2c649b4d4
 ---> ec0d62e6d76d
Step 5/6 : FROM base AS step2
 ---> 0f81232dc95d
Step 6/6 : RUN echo "step2"
 ---> Running in 7f3de2e21bb8
step2
Removing intermediate container 7f3de2e21bb8
 ---> 426d0a2abc9a
Successfully built 426d0a2abc9a
```

It looks like `step1` has been run too, even though it should have been skipped.

Let's change `FROM base AS step2` to `FROM ubuntu AS step2` in the `Dockerfile` example and build `step2`:

```Dockerfile
FROM ubuntu AS base
RUN echo "base"

FROM base AS step1
RUN echo "step1"

FROM ubuntu AS step2
RUN echo "step2"
```

`DOCKER_BUILDKIT=0 docker build --no-cache -f Dockerfile --target step2 .`:

```console
Sending build context to Docker daemon  178.7kB
Step 1/6 : FROM ubuntu AS base
 ---> a7870fd478f4
Step 2/6 : RUN echo "base"
 ---> Running in 32ed2ee444d3
base
Removing intermediate container 32ed2ee444d3
 ---> 802165f5e8cb
Step 3/6 : FROM base AS step1
 ---> 802165f5e8cb
Step 4/6 : RUN echo "step1"
 ---> Running in 2b66f46be714
step1
Removing intermediate container 2b66f46be714
 ---> babac8e05c0c
Step 5/6 : FROM ubuntu AS step2
 ---> a7870fd478f4
Step 6/6 : RUN echo "step2"
 ---> Running in a8b0caf2afc2
step2
Removing intermediate container a8b0caf2afc2
 ---> 492584095b20
Successfully built 492584095b20
```

Without BuildKit, Docker multi-stage builds execute all the stages from the beginning of the Dockerfile up to the specified
stage, even if some stages are not dependencies of the requested stage.

As a hint, the output of `docker build` command is different when BuildKit is enabled, as the steps of each build stage
are present in the output (`[step2 1/2]`). Knowing how to detect if BuildKit is enabled by inspecting output can be helpful
when debugging.

## Using multi-stage builds without BuildKit

Multi-stage builds can be used without BuildKit, but the Dockerfile ends up obfuscated:

```Dockerfile
ARG BUILD_STEP

FROM ubuntu AS step0

RUN echo "step0"

ENV BUILD=0

FROM ubuntu AS step1

RUN echo "step1"

ENV BUILD=1

FROM step${BUILD_STEP} AS final

RUN echo "RUNNING ${BUILD_STEP}"

RUN if [ $BUILD -eq 0 ]; then echo "run step0"; fi
RUN if [ $BUILD -eq 1 ]; then echo "run step1"; fi
```

- `DOCKER_BUILDKIT=0 docker build --no-cache -f Dockerfile-env . --build-arg BUILD_STEP=1`:

```console
Sending build context to Docker daemon    106kB
Step 1/11 : ARG BUILD_STEP
Step 2/11 : FROM ubuntu AS step0
 ---> a7870fd478f4
Step 3/11 : RUN echo "step0"
 ---> Running in 6820fd9ac876
step0
Removing intermediate container 6820fd9ac876
 ---> 17173a835754
Step 4/11 : ENV BUILD=0
 ---> Running in fbb156a22f51
Removing intermediate container fbb156a22f51
 ---> 1d3b65ee6ad3
Step 5/11 : FROM ubuntu AS step1
 ---> a7870fd478f4
Step 6/11 : RUN echo "step1"
 ---> Running in ccd8eca78e6f
step1
Removing intermediate container ccd8eca78e6f
 ---> ad2b0ed7b746
Step 7/11 : ENV BUILD=1
 ---> Running in 11100840b220
Removing intermediate container 11100840b220
 ---> 98116c53f3f0
Step 8/11 : FROM step${BUILD_STEP} AS final
 ---> 98116c53f3f0
Step 9/11 : RUN echo "RUNNING ${BUILD_STEP}"
 ---> Running in a85bcd9fb718
RUNNING 
Removing intermediate container a85bcd9fb718
 ---> ae0f32f2a153
Step 10/11 : RUN if [ $BUILD -eq 0 ]; then echo "run step0"; fi
 ---> Running in 95340973ab8e
Removing intermediate container 95340973ab8e
 ---> 5e59e548560d
Step 11/11 : RUN if [ $BUILD -eq 1 ]; then echo "run step1"; fi
 ---> Running in ce0d6ffff971
run step1
Removing intermediate container ce0d6ffff971
 ---> 159c976b774b
Successfully built 159c976b774b
```

All steps of the Dockerfile are executed (including `step0`), but because of `FROM step${BUILD_STEP} AS final` and `--build-arg BUILD_STEP=1`,
in the `final` step, `BUILD=1` since `FROM step1 AS final`.

- `DOCKER_BUILDKIT=1 docker build --no-cache -f Dockerfile-env . --build-arg BUILD_STEP=1`

```console
[+] Building 0.7s (9/9) FINISHED                                                                                                                                                                                
 => [internal] load build definition from Dockerfile-env                                                                                                                                                   0.0s
 => => transferring dockerfile: 41B                                                                                                                                                                        0.0s
 => [internal] load .dockerignore                                                                                                                                                                          0.0s
 => => transferring context: 2B                                                                                                                                                                            0.0s
 => [internal] load metadata for docker.io/library/ubuntu:latest                                                                                                                                           0.0s
 => CACHED [step1 1/2] FROM docker.io/library/ubuntu                                                                                                                                                       0.0s
 => [step1 2/2] RUN echo "step1"                                                                                                                                                                           0.1s
 => [final 1/3] RUN echo "RUNNING ${BUILD_STEP}"                                                                                                                                                           0.2s
 => [final 2/3] RUN if [ 1 -eq 0 ]; then echo "run step0"; fi                                                                                                                                              0.2s
 => [final 3/3] RUN if [ 1 -eq 1 ]; then echo "run step1"; fi                                                                                                                                              0.2s
 => exporting to image                                                                                                                                                                                     0.0s
 => => exporting layers                                                                                                                                                                                    0.0s
 => => writing image sha256:648f3fdac0c4160c072caf50f59bf34219230c56e420bf1727f3bfa4747da883                                                                                                               0.0s
```

Only the `final` step and its dependencies (`step1`) are executed, so `BUILD=1` here too in the
`final` step. `step0` is not executed.

## Conclusion

Docker multi-stage builds should only be used together with BuildKit, since using them without BuildKit leads to
surprising results.
