-- Listen DNS
addLocal("0.0.0.0:{{FRONTEND_PORT}}")
addLocal("[::]:{{FRONTEND_PORT}}")

-- Console
setKey("{{DNSDIST_KEY}}")
controlSocket("127.0.0.1:5199")

-- Performance
setRingBuffersSize(1000000)

setMaxUDPOutstanding({{UDP_OUTSTANDING}})
setMaxTCPClientThreads({{TCP_THREADS}})
setMaxTCPQueuedConnections({{TCP_QUEUE}})
setMaxTCPConnectionsPerClient(20)

-- Backend
newServer({
    address="127.0.0.1:{{RECURSIVE_PORT}}",
    name="unbound-v4"
})

newServer({
    address="[::1]:{{RECURSIVE_PORT}}",
    name="unbound-v6"
})

setServerPolicy(leastOutstanding)

-- Packet Cache
pc = newPacketCache({{PACKET_CACHE}},{
    maxTTL=86400,
    minTTL=60,
    temporaryTTL=30,
    maxNegativeTTL=300
})

getPool(""):setCache(pc)

----------------------------------------------------
-- Blocklist
----------------------------------------------------

local blocklistKVS = newCDBKVStore("/opt/blocklist/domains.cdb",60)

local qnameLookupKey = KeyValueLookupKeyQName(false)
local suffixLookupKey = KeyValueLookupKeySuffix(2,false)

----------------------------------------------------
-- Whitelist
----------------------------------------------------

local whitelistSMN = newSuffixMatchNode()

whitelistSMN:add(newDNSName("bri.co.id."))

addAction(
    SuffixMatchNodeRule(whitelistSMN),
    PoolAction("")
)

----------------------------------------------------
-- Block AAAA
----------------------------------------------------

addAction(
    AndRule({
        KeyValueStoreLookupRule(blocklistKVS,suffixLookupKey),
        QTypeRule(DNSQType.AAAA)
    }),
    SpoofAction({{SPOOF_IPV6}})
)

----------------------------------------------------
-- Block A
----------------------------------------------------

addAction(
    AndRule({
        KeyValueStoreLookupRule(blocklistKVS,suffixLookupKey),
        QTypeRule(DNSQType.A)
    }),
    SpoofAction({{SPOOF_IPV4}})
)

----------------------------------------------------
-- Rate Limit
----------------------------------------------------

{{RATELIMIT}}

----------------------------------------------------
-- Forward Normal DNS
----------------------------------------------------

addAction(AllRule(),PoolAction(""))

----------------------------------------------------
-- Disable Security Poll
----------------------------------------------------

setSecurityPollSuffix("")

----------------------------------------------------
-- ACL
----------------------------------------------------

{{DNSDIST_ACL}}

----------------------------------------------------
-- Web API
----------------------------------------------------

webserver("0.0.0.0:8083")

setWebserverConfig({
    password="{{DNSDIST_WEB_PASSWORD}}",
    apiKey="{{DNSDIST_API_KEY}}",
    acl="{{DNSDIST_WEB_ACL}}"
})

----------------------------------------------------
-- Query Log
----------------------------------------------------

{{QUERYLOG}}
