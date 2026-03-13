FROM alpine:3.20

WORKDIR /app

COPY poll_stiebel_isg.sh /app/poll_stiebel_isg.sh

RUN apk add --no-cache mosquitto-clients curl \
    && sed -i 's/\r$//' /app/poll_stiebel_isg.sh \
    && chmod +x /app/poll_stiebel_isg.sh

CMD ["sh", "/app/poll_stiebel_isg.sh"]

