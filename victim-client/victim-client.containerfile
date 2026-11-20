FROM docker.io/alpine:3.23

RUN apk add --no-cache iproute2 python3

COPY entrypoint.sh /entrypoint.sh
COPY server.py /server.py
RUN chmod +x /entrypoint.sh /server.py

ENTRYPOINT [ "/entrypoint.sh" ]
