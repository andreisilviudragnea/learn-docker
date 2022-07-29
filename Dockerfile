FROM ubuntu AS base

RUN echo "base" > base

FROM base AS step1

COPY --from=base base .

RUN echo "step1" >> base && cat base

FROM base AS step2

COPY --from=base base .

RUN echo "step2" >> base && cat base
