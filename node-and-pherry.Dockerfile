FROM ubuntu:20.04 AS base

ARG DEBIAN_FRONTEND='noninteractive'
# ARG RUST_TOOLCHAIN='nightly-2021-07-03'
ARG RUST_TOOLCHAIN='stable'
ARG PHALA_GIT_REPO='https://github.com/j-szulc/phala-blockchain'
ARG PHALA_GIT_TAG_BASE='master'
# ARG PHALA_GIT_TAG='poc'

WORKDIR /root

RUN apt-get update && \
    apt-get install -y apt-utils apt-transport-https software-properties-common readline-common curl vim wget gnupg gnupg2 gnupg-agent ca-certificates cmake pkg-config libssl-dev git build-essential llvm clang libclang-dev

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain="${RUST_TOOLCHAIN}" && \
    $HOME/.cargo/bin/rustup target add wasm32-unknown-unknown --toolchain "${RUST_TOOLCHAIN}"

RUN echo "Compiling Phala Blockchain from $PHALA_GIT_REPO:$PHALA_GIT_TAG_BASE..." && \
    git clone --depth 1 --recurse-submodules --shallow-submodules -j 8 -b ${PHALA_GIT_TAG_BASE} ${PHALA_GIT_REPO} phala-blockchain && \
    cd phala-blockchain && \
    PATH="$HOME/.cargo/bin:$PATH" cargo build

## neccessary due to an open bug in rustc
## https://github.com/rust-lang/rust/issues/84970
RUN cd phala-blockchain && \ 
    PATH="$HOME/.cargo/bin:$PATH" cargo clean -p phala-node-runtime && \
    PATH="$HOME/.cargo/bin:$PATH" cargo clean -p phala-node

FROM base AS builder

## If any modifications have been made on top of master,
## to avoid unneccesary recompilation
## this script will checkout $PHALA_GIT_TAG branch
## and apply incremental build

ARG PHALA_GIT_REPO='https://github.com/j-szulc/phala-blockchain'
ARG PHALA_GIT_TAG='master'

RUN echo "Applying $PHALA_GIT_REPO:$PHALA_GIT_TAG branch..." && \
    cd phala-blockchain && \
    git checkout $PHALA_GIT_TAG && \
    PATH="$HOME/.cargo/bin:$PATH" cargo build

RUN cd phala-blockchain && \
    cp ./target/debug/phala-node /root && \
    cp ./target/debug/pherry /root && \
    PATH="$HOME/.cargo/bin:$PATH" cargo clean && \
    rm -rf /root/.cargo/registry && \
    rm -rf /root/.cargo/git 

# ====

FROM ubuntu:20.04 as node

ARG DEBIAN_FRONTEND='noninteractive'

WORKDIR /root

RUN apt-get update && \
    apt-get install -y apt-utils apt-transport-https software-properties-common readline-common curl vim wget gnupg gnupg2 gnupg-agent ca-certificates tini

COPY --from=builder /root/phala-node .
ADD dockerfile.d/start_node.sh ./start_node.sh

ENV RUST_LOG="info"
ENV CHAIN="phala"
ENV NODE_NAME='phala-node'
ENV NODE_ROLE="FULL"
ENV EXTRA_OPTS=''

EXPOSE 9615
EXPOSE 9933
EXPOSE 9944
EXPOSE 30333

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["/bin/bash", "./start_node.sh"]

# ====

FROM ubuntu:20.04 as pherry

ARG DEBIAN_FRONTEND='noninteractive'

WORKDIR /root

RUN apt-get update && \
    apt-get install -y apt-utils apt-transport-https software-properties-common readline-common curl vim wget gnupg gnupg2 gnupg-agent ca-certificates tini

COPY --from=builder /root/pherry .
ADD dockerfile.d/start_pherry.sh ./start_pherry.sh

ENV RUST_LOG="info"
ENV PRUNTIME_ENDPOINT='http://127.0.0.1:8000'
ENV PHALA_NODE_WS_ENDPOINT='ws://127.0.0.1:9944'
ENV MNEMONIC=''
ENV EXTRA_OPTS='-r'
ENV SLEEP_BEFORE_START=0

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["/bin/bash", "./start_pherry.sh"]
