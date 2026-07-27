server:

    ####################################
    # Interface
    ####################################

    interface: 127.0.0.1
    interface: ::1
    port: {{RECURSIVE_PORT}}

    ####################################
    # Protocol
    ####################################

    do-ip4: yes
    do-ip6: {{DO_IPV6}}
    do-udp: yes
    do-tcp: yes

    ####################################
    # ACL
    ####################################

{{ACL}}

    ####################################
    # Root
    ####################################

    root-hints: "/usr/share/dns/root.hints"

    ####################################
    # Privacy
    ####################################

    hide-identity: yes
    hide-version: yes

    ####################################
    # Cache
    ####################################

    prefetch: yes
    prefetch-key: yes
    qname-minimisation: yes

    cache-max-ttl: 86400
    cache-min-ttl: 60

    serve-expired: yes
    serve-expired-ttl: 86400

    ####################################
    # Threads
    ####################################

    num-threads: {{THREAD}}

    ####################################
    # Memory Cache
    ####################################

    rrset-cache-size: {{RRSET_CACHE}}
    msg-cache-size: {{MSG_CACHE}}

    rrset-cache-slabs: {{SLABS}}
    msg-cache-slabs: {{SLABS}}
    infra-cache-slabs: {{SLABS}}
    key-cache-slabs: {{SLABS}}

    infra-cache-numhosts: {{INFRA_CACHE}}

    ####################################
    # Performance
    ####################################

    so-reuseport: yes

    so-rcvbuf: 16m
    so-sndbuf: 16m

    outgoing-range: {{OUTGOING_RANGE}}
    num-queries-per-thread: {{NUM_QUERIES}}

    outgoing-num-tcp: 100
    incoming-num-tcp: 100

    edns-buffer-size: 1232

    ####################################
    # Domain Insecure
    ####################################

    domain-insecure: "nsgt.bri.co.id"
    domain-insecure: "bri.co.id"
    domain-insecure: "bni.co.id"
    domain-insecure: "bankmandiri.co.id"
    domain-insecure: "btn.co.id"
    domain-insecure: "permatabank.com"
    domain-insecure: "danamon.co.id"
    domain-insecure: "bca.co.id"

    domain-insecure: "gopay.co.id"
    domain-insecure: "gojek.com"
    domain-insecure: "ovo.id"
    domain-insecure: "dana.id"
    domain-insecure: "linkaja.id"
    domain-insecure: "shopeepay.co.id"

    domain-insecure: "midtrans.com"
    domain-insecure: "xendit.co"
    domain-insecure: "duitku.com"
    domain-insecure: "faspay.co.id"

    domain-insecure: "tokopedia.com"
    domain-insecure: "shopee.co.id"
    domain-insecure: "bukalapak.com"
    domain-insecure: "lazada.co.id"

    domain-insecure: "telkomsel.com"
    domain-insecure: "indosatooredoo.com"
    domain-insecure: "xl.co.id"

    ####################################
    # Logging
    ####################################

{{QUERY_LOG}}
