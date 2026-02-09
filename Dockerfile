# performance metric uploading daemon
# handles -march= / -mtune= architecture-specific distribution

#FROM debian:bookworm-slim
FROM python:3.13-slim

RUN apt-get update                             \
&&  apt-get install -y --no-install-recommends \
    linux-perf                                 \
    autofdo                                    \
    apt-file                                   \
    curl                                       \
    ca-certificates                            \
&&  rm -rf /var/lib/apt/lists/*

RUN apt-file update
#RUN ln -sv /usr/bin/perf_$(ls /usr/bin | grep -oP '(?<=perf_)\d+\.\d+' | head -n 1) /usr/bin/perf \
#||  ln -sv /usr/bin/linux-perf                                                      /usr/bin/perf
RUN test -e /usr/bin/perf

COPY performance_metric_uploading_daemon/performance_metric_uploading_daemon.sh /usr/local/bin/performance_metric_uploading_daemon.sh
RUN chmod -v +x /usr/local/bin/performance_metric_uploading_daemon.sh
# TODO create looping script ?
ENTRYPOINT ["/bin/bash", "-c", "while true; do /usr/local/bin/performance_metric_uploading_daemon.sh; sleep 3600; done"]
