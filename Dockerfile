FROM ubuntu AS base
RUN echo "base"

FROM base AS step1
RUN echo "step1"

FROM base AS step2
RUN echo "step2"
