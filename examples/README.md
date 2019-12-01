# Testing load balancing

## Takeaways

- Need to explicitly enable client side load balancing.
  - Ruby: When creating client stub `channel_args: {'grpc.lb_policy_name' => 'round_robin'}`
  - Java: When building the channel `.defaultLoadBalancingPolicy("round_robin")`
- gRPC will handle broken tcp connections and [retries](https://github.com/grpc/proposal/blob/master/A6-client-retries.md) under the hood
- Without client load balancing
  - gRPC will make a tcp connection to only one of the server IPs
  - When that connection is broken, gRPC will try to connect to another server IP
- With round robin client load balancing ([grpc.lb_policy_name="round_robin"](https://github.com/grpc/grpc/blob/master/include/grpc/impl/codegen/grpc_types.h))
  - gRPC will connect to all server IPs

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

Make sure you're _not_ connected the VPN

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

## Teardown

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
GRPC_PORT=50051 bundle exec ruby greeter_server.rb
```

```
GRPC_PORT=50052 bundle exec ruby greeter_server.rb
```

Start the client. Hit `ENTER` to send another request. Type any character and hit `ENTER` to quit

```
GRPC_VERBOSITY=debug GRPC_TRACE=cares_resolver,glb bundle exec ruby greeter_client.rb
```

# Misc

When running the client/server, use `GRPC_VERBOSITY` and `GRPC_TRACE` for extra debug info. See [docs](https://github.com/grpc/grpc/blob/master/doc/environment_variables.md)

For example, the ruby example can be run with the following options

```
GRPC_VERBOSITY=debug GRPC_TRACE=cares_resolver,glb bundle exec ruby greeter_client.rb
```

# gRPC Server Graceful Shutdown

Make Cleanup all the things from the load balancing test and point the client to `localhost`

## Takeaways

- Ruby server can be run with `run_till_terminated_or_interrupted` that listens for the passed in signals.
  - If a signal is caught, it starts to gracefully shut down the server
  - During graceful shutdown, new requests will be rejected with code 14), and existing requests are allowed to finish.
  - Make sure to set a reasonable `poll_period` when initializing the server (default 1s)
    - `poll_period` is the amount of time to wait before cancelling RPCs during graceful shutdown.
    - When `poll_period` expires, server will send `FIN` packet to client to initiate TCP connection termination.
      - The client application code will receive a `14:Socket Closed` error
- If the client sends a new RPC on the same TCP connection after the server sends a GOAWAY
  - The server will just ignore the new RPC
  - The client thinks the RPC is in progress and waits
  - Once the server gracefully shuts down, the clients gets the `14:Socket Closed` error

## Edgecase where client sends an RCP on same TCP connection after server sends GOAWAY

### Setup

Create a dummy pipe with a 1 second delay

```
sudo dnctl pipe 1 config bw 1000Kbit/s delay 1000
```

Add the following line to `/etc/pf.conf` to send all TCP traffic through the dummy pipe

```
dummynet out proto tcp from any to any pipe 1
```

Load and enable packet filtering via the `pfctl` instructions above.

### Ruby

Ensure that `parallel_requests_with_sigint` is uncommented and the channel name is `localhost:50051`.

Run the server

```
GRPC_PORT=50051 HELLO_SLEEP=10 bundle exec ruby greeter_server.rb
```

Get its process id

```
ps | grep ruby
```

Start recording the loopback interface `lo0` traffic in Wireshark.

Run the client and pass in the server's process id

```
SERVER_PROCESS_ID=__server_process_id__ bundle exec ruby greeter_client.rb
```

When you see that the first request is received by the server, `CTRL+C` the client, which will send `SIGINT` the server and send a parallel request to the server.

In Wireshark, you should see the server send a `GOAWAY` frame. Before that frame is ACK'd, the client should have sent another RPC request.

### Teardown

Remove the line that was added to `/etc/pf.conf` and disable packet filtering

Delete the pipe

```
sudo dnctl pipe delete 1
```

# NewRelic

## Ruby

Start server

```
NEW_RELIC_LICENSE_KEY=__your_key__ NEW_RELIC_CONFIG_PATH=config/newrelic-server.yml GRPC_PORT=50051 bundle exec ruby greeter_server.rb
```

Run client

```
NEW_RELIC_LICENSE_KEY=__your_key__ NEW_RELIC_CONFIG_PATH=config/newrelic-client.yml bundle exec ruby greeter_client.rb
```

# NGINX when shutting down container with SIGTERM

## Background Knowledge

- `my_init` is a python3 [wrapper script](https://github.com/phusion/baseimage-docker/blob/master/image/bin/my_init) around `runsvdir` and `sv` that can catch signals and gracefully shutdown the services that are run by `runsvdir`
- `runsvdir` is a daemon that looks for changes in the configured `service` directory (`/etc/service`) and spins up a `runsv` process for each detected service
- `runsv` manages a single service's lifecycle

  - Notable features
    - Restarts the child service process if it dies
    - Accepts commands to stop, start, restart, etc the service (see [the man page](http://smarden.org/runit/runsv.8.html))
      - Commands are issued by writing the desired command character to a named pipe (file) at `/etc/service/__your_service__/supervise/control`
      - Command behavior can be customized by including a script named the same as the command you are overriding in `/etc/service/__your_service__/control/`
      - We are interested in overriding the SIGTERM behavior for nginx, so we have the script `/etc/service/nginx/control/t`

- `sv` is a command line tool that makes it easier to interact with the `runsv` processes

  - Notable features (see [the man page](http://smarden.org/runit/sv.8.html) for more)
    - Has a `force-stop` command that sends SIGTERM to the service, then kill it after some timeout (can be configured via the `-w` flag)

- `my_init` uses `sv force-stop -w KILL_PROCESS_TIMEOUT /etc/service/*` to gracefully shutdown the services.
  - `KILL_PROCESS_TIMEOUT` is an env variable that can be customized (we should set it to something like 30 or 60 seconds)
- Can customize the control of [runsv](http://smarden.org/runit/runsv.8.html) that is used by `my_init` to turn the TERM signal into a SIGQUIT signal for NGINX to allow it to gracefully shutdown.
  - Otherwise, if NGINX receives a SIGTERM, it will do a fast shutdown on SIGTERM and does not gracefully shutdown existing gRPC requests

## Takeaways

- Possible to configure `runsv` to gracefully shutdown NGINX (see `server_infra/docker/base/build/service/nginx/control/t`)
- ⚠️ NGINX graceful shutdown still results in gRPC client errors
  - During graceful shutdown, NGINX responds with TCP FIN for new connections (TCP SYN)
  - However, gRPC server sends TCP RST for new connections during graceful shutdown
  - gRPC client handles TCP FIN by immediately trying to reconnect without any backoff (https://grpc.io/blog/grpc_on_http2/)
  - This causes a flood of TCP SYN packets as the gRPC client tries to re-establish a connection with that IP address
  - This also causes `14:Socket closed` errors after NGINX has shutdown
- For ECS, we should remember to configure the docker stop graceperiod ([StopTimeout](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ecs-taskdefinition-containerdefinitions.html#cfn-ecs-taskdefinition-containerdefinition-stoptimeout)) to be the same or slightly longer than `KILL_PROCESS_TIMEOUT`

## Ruby

Build the docker file

```
docker build -t grpc/examples/ruby/greeter_server -f server.Dockerfile .
```

Run a server at port 50051

```
docker run -p 50051:3000 -e GRPC_PORT=50061 -e KILL_PROCESS_TIMEOUT=300 -e HELLO_SLEEP=20 grpc/examples/ruby/greeter_server
```

Run the client (point to port 50051)

Find the docker container with `docker ps` and stop it with `docker stop --time 300 __container_id__` which sends a SIGTERM (same as ECS).

# my_init run script with exec

## Takeaways

- The `run` script should start the daemon with `exec ...`, otherwise the process doesn't get shutdown properly by `sv force-stop`
- The negative one process id in the [my_init](https://github.com/phusion/baseimage-docker/blob/master/image/bin/my_init) python code sends that command to all child processes.
- Without exec, sv cannot properly shutdown the process, which means that our ruby code would not get the SIGTERM as a part of the call to sv force-stop. However, my_init has its own custom logic to kill all child processes with SIGTERM then SIGKILL (https://github.com/phusion/baseimage-docker/blob/master/image/bin/my_init#L226).
  - So without exec, NGINX will gracefully shutdown on sv force-stop while the gRPC server continues going. Then whenever NGINX has shutdown, my_init script will then stop all child processes which will shutdown the gRPC server.
  - With exec, both NGINX and our gRPC server will gracefully shutdown at the same time, and the gRPC server will have been stopped by the time my_init tries to stop all child processes.
  - The end behavior is the same, but without exec we are relying on the code of my_init instead of supervisor

## Ruby

Remove the first `exec` from `exec bundle exec ruby greeter_server.rb` in the greeter_server service `run` file

Comment out the `s.run_till_terminated_or_interrupted` line and uncomment the block of code for `exec` testing.

Build the docker image and run it the same way as the NGINX graceful shutdown test above. You should see the line "Hello from process .." being printed.

Start a bash terminal for the running docker container

```
docker exec -it __container_id__ /bin/bash
```

Tell supervisor to shutdown the greeter_server service

```
/usr/bin/sv force-stop /etc/service/greeter_server
```

Notice that the service is stopped "successfully", but the "Hello..." lines are still being printed.

Tell supervisor to start the greeter_server service

```
/usr/bin/sv start /etc/service/greeter_server
```

Notice that now there are two processes outputing the "Hello..." lines.

# TLS

## Resources

- https://github.com/codequest-eu/grpc-demo/blob/master/server/server.rb
- https://github.com/grpc/grpc/blob/master/src/ruby/qps/client.rb

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
