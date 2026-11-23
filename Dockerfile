# Original credit: https://github.com/jpetazzo/dockvpn

# Smallest base image
FROM alpine:3.24

LABEL maintainer="Jerry Lau <liushipu@icloud.com>"

# Testing: pamtester（apk 使用清华源）
# Alpine 3.19+ 的 iptables 默认走 nf_tables；群晖等旧内核无 MASQUERADE/nft 支持。
# 安装 iptables-legacy，由 ovpn_run 优先选用（与 kylemanna/openvpn:2.4 行为一致）。
RUN printf '%s\n' \
        'https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.24/main' \
        'https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.24/community' \
        'https://mirrors.tuna.tsinghua.edu.cn/alpine/edge/testing' \
        > /etc/apk/repositories && \
    apk add --update 'openvpn>=2.7.7' 'openvpn<2.8.0' iptables iptables-legacy bash easy-rsa openvpn-auth-pam google-authenticator pamtester libqrencode && \
    ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*

# Needed by scripts
ENV OPENVPN=/etc/openvpn
ENV EASYRSA=/usr/share/easy-rsa \
    EASYRSA_BATCH=1 \
    EASYRSA_CRL_DAYS=3650 \
    EASYRSA_PKI=$OPENVPN/pki

VOLUME ["/etc/openvpn"]

# Internally uses port 1194/udp, remap using `docker run -p 443:1194/tcp`
EXPOSE 1194/udp

CMD ["ovpn_run"]

ADD ./bin /usr/local/bin
RUN chmod a+x /usr/local/bin/*

# Add support for OTP authentication using a PAM module
ADD ./otp/openvpn /etc/pam.d/
