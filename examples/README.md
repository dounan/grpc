# Testing load balancing

## Setup

Create a new file `/etc/dounan_hosts` with

```
127.1.0.1 grpc.dounan.test
127.1.0.2 grpc.dounan.test
```

```
brew install dnsmasq
```

Set `addn-hosts=` to `dounan_hosts` in `/usr/local/etc/dnsmasq.conf`

```
addn-hosts=/etc/dounan_hosts
```

Start dnsmasq

```
sudo brew services start dnsmasq
```

Change your DNS server in Network Preferences to `127.0.0.1`

Ensure that dnsmasq and the hosts file is configured correctly

```
dig name grpc.dounan.test @127.0.0.1
```

Add entries to `/etc/pf.conf` below the `rdr-anchor` line

```
rdr on lo0 proto tcp from any to 127.1.0.1 port 50050 -> 127.0.0.1 port 50051
rdr on lo0 proto tcp from any to 127.1.0.2 port 50050 -> 127.0.0.1 port 50052
```

Load the pf.conf file and enable pf

```
sudo pfctl -f /etc/pf.conf
sudo pfctl -e
```

## Cleanup

Disable pf

```
sudo pfctl -d
```

Delete the lines added above to `/etc/pf.conf`

Delete `127.0.0.1` from your DNS servers in Network Preferences

Stop dnsmasq

```
sudo brew services stop dnsmasq
```

## Ruby

Start two servers

```
PORT=50051 bundle exec ruby greeter_server.rb
```

```
PORT=50052 bundle exec ruby greeter_server.rb
```

Start the client. Hit `ENTER` to send another request. Type any character and hit `ENTER` to quit

```
GRPC_VERBOSITY=debug GRPC_TRACE=cares_resolver,glb bundle exec ruby greeter_client.rb
```

## Learnings

- gRPC will handle broken tcp connections and [retries](https://github.com/grpc/proposal/blob/master/A6-client-retries.md) under the hood

### Without client load balancing

- gRPC will make a tcp connection to only one of the server IPs
- When that connection is broken, gRPC will try to connect to another server IP

### With round robin client load balancing ([grpc.lb_policy_name="round_robin"](https://github.com/grpc/grpc/blob/master/include/grpc/impl/codegen/grpc_types.h))

- gRPC will connect to all server IPs

# Misc

When running the client/server, use `GRPC_VERBOSITY` and `GRPC_TRACE` for extra debug info. See [docs](https://github.com/grpc/grpc/blob/master/doc/environment_variables.md)

For example, the ruby example can be run with the following options

```
GRPC_VERBOSITY=debug GRPC_TRACE=cares_resolver,glb bundle exec ruby greeter_client.rb
```

# NewRelic

## Ruby

Start server

```
NEW_RELIC_LICENSE_KEY=__your_key__ NEW_RELIC_CONFIG_PATH=config/newrelic-server.yml PORT=50051 bundle exec ruby greeter_server.rb
```

Run client

```
NEW_RELIC_LICENSE_KEY=__your_key__ NEW_RELIC_CONFIG_PATH=config/newrelic-client.yml bundle exec ruby greeter_client.rb
```

# === Original README ===

# Examples

This directory contains code examples for all the C-based gRPC implementations: C++, Node.js, Python, Ruby, Objective-C, PHP, and C#. You can find examples and instructions specific to your
favourite language in the relevant subdirectory.

Examples for Go and Java gRPC live in their own repositories:

- [Java](https://github.com/grpc/grpc-java/tree/master/examples)
- [Android Java](https://github.com/grpc/grpc-java/tree/master/examples/android)
- [Go](https://github.com/grpc/grpc-go/tree/master/examples)

For more comprehensive documentation, including an [overview](https://grpc.io/docs/) and tutorials that use this example code, visit [grpc.io](https://grpc.io/docs/).

## Quick start

Each example directory has quick start instructions for the appropriate language, including installation instructions and how to run our simplest Hello World example:

- [C++](cpp)
- [Ruby](ruby)
- [Node.js](node)
- [Python](python/helloworld)
- [C#](csharp)
- [Objective-C](objective-c/helloworld)
- [PHP](php)
