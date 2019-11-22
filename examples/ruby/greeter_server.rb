#!/usr/bin/env ruby

# Copyright 2015 gRPC authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Sample gRPC server that implements the Greeter::Helloworld service.
#
# Usage: $ path/to/greeter_server.rb

this_dir = File.expand_path(File.dirname(__FILE__))
lib_dir = File.join(this_dir, 'lib')
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)

require 'grpc'
require 'helloworld_services_pb'
require 'newrelic_rpm'

# GreeterServer is simple server that implements the Helloworld Greeter server.
class GreeterServer < Helloworld::Greeter::Service
  # say_hello implements the SayHello rpc method.
  def say_hello(hello_req, _unused_call)
    $stderr.puts "Received say_hello: #{hello_req}"

    # # Wait for user input before returning
    # puts "Waiting for user input..."
    # gets

    sleep (ENV['HELLO_SLEEP'] || "0").to_i

    Helloworld::HelloReply.new(message: "Hello #{hello_req.name}")
  end
end

# main starts an RpcServer that receives requests to GreeterServer at the sample
# server port.
def main
  s = GRPC::RpcServer.new(
    interceptors: [NewRelicInterceptor.new],

    # Amount of time to wait before cancelling RPCs during graceful shutdown
    # https://www.rubydoc.info/gems/grpc/GRPC/RpcServer#initialize-instance_method
    poll_period: 30,
  )

  s.add_http2_port('0.0.0.0:' + (ENV['GRPC_PORT'] || "50051"), :this_port_is_insecure)
  s.handle(GreeterServer)

  $stderr.puts "Starting greeter server...#{Time.now.inspect}"

  # Runs the server with SIGHUP, SIGINT and SIGQUIT signal handlers to
  #   gracefully shutdown.
  # User could also choose to run server via call to run_till_terminated
  s.run_till_terminated_or_interrupted([1, 'int', 'SIGQUIT', 'term'])

  #############################################################################
  ## Testing out whether or not `exec` is required in our service `run` file.
  ## Run this code instead of the gRPC server

  # interrupted = false
  # Signal.trap("INT") do
  #   interrupted = true
  # end
  # Signal.trap("QUIT") do
  #   interrupted = true
  # end
  # Signal.trap("TERM") do
  #   interrupted = true
  # end
  # while not interrupted
  #   $stderr.puts "Hello from process #{Process.pid}"
  #   sleep 1
  # end
  #############################################################################

  $stderr.puts "Stopped greeter server at #{Time.now.inspect}"
end

class NewRelicInterceptor < GRPC::ServerInterceptor
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation
  # Intercept a unary request response call
  #
  # @param [Object] request
  # @param [GRPC::ActiveCall] call
  # @param [Method] method
  #
  def request_response(request: nil, call: nil, method: nil)
    # https://www.rubydoc.info/github/newrelic/rpm/NewRelic/Agent/Instrumentation/ControllerInstrumentation
    perform_action_with_newrelic_trace(name: method.name, class_name: method.owner) do
      yield
    end
  end
end

main
