FROM scratch
ARG TARGETARCH
COPY icecast-linux-${TARGETARCH} /usr/local/bin/icecast
ENTRYPOINT ["/usr/local/bin/icecast"]
CMD ["-v"]
