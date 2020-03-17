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

# Sample app that connects to a Greeter service.
#
# Usage: $ path/to/greeter_client.rb

this_dir = File.expand_path(File.dirname(__FILE__))
lib_dir = File.join(this_dir, 'lib')
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)

require 'grpc'
require 'helloworld_services_pb'
require 'newrelic_rpm'

def main
  # https://discuss.newrelic.com/t/custom-metrics-have-no-data-or-are-missing/74219/3
  # https://github.com/newrelic/rpm/blob/418d9b854b4e65cddd9dbd10a4bc55cb4ceb5eb3/lib/new_relic/agent.rb#L353
  # NewRelic::Agent.manual_start(sync_startup: true)
  # The sync_startup solution doesn't work so...
  # sleep(5)

  ssl_cert = File.open("certs/server.crt").read
  channel_credentials = GRPC::Core::ChannelCredentials.new(ssl_cert)

  host = ENV["HOST"] || 'localhost:50051';

  puts "host: #{host}"
  stub = Helloworld::Greeter::Stub.new(
    host,
    ENV["SSL_ENABLED"] ? channel_credentials : :this_channel_is_insecure,

    # https://github.com/grpc/grpc/blob/master/include/grpc/impl/codegen/grpc_types.h
    channel_args: {
      'grpc.lb_policy_name' => 'round_robin',
      'grpc.dns_min_time_between_resolutions_ms' => 1000,
      # 'grpc.dns_enable_srv_queries' => 1,
    },
    interceptors: [NewRelicInterceptor.new],
  )

  name = ARGV.size > 0 ?  ARGV[0] : 'world'

  # Only one of these should be uncommented
  # parallel_requests_with_sigint(stub, name)
  user_input_controlled_requests(stub, name)
end

def parallel_requests_with_sigint(stub, name)
  t1 = Thread.new do
    say_hello(stub, name, "Initial")
  end

  trapped = false

  Signal.trap("INT") do
    Thread.new do
      system("kill -2 #{ENV["SERVER_PROCESS_ID"]}")
      sleep 0.2
      say_hello(stub, name, "Parallel")
    end.join
    trapped = true
  end

  while !trapped
  end

  t1.join
end

def user_input_controlled_requests(stub, name)
  result = ""
  count = 1

  while result == ""
    puts "Waiting for user input..."
    result = gets.strip
    say_hello(stub, name, count)
    count += 1
  end
end

def say_hello(stub, name, label)
  begin
    p "[#{label}] Calling say_hello..."
    message = stub.say_hello(Helloworld::HelloRequest.new(name: name), deadline: Time.now + 100).message
    p "[#{label}] Greeting: #{message}"
  rescue GRPC::BadStatus => e
    p "[#{label}] Greeting failed: #{e}"
  end
end

class NewRelicInterceptor < GRPC::ClientInterceptor

  # @param [Object] request
  # @param [GRPC::ActiveCall] call
  # @param [Method] method
  # @param [Hash] metadata
  def request_response(request: nil, call: nil, method: nil, metadata: nil)
    # https://docs.newrelic.com/docs/agents/ruby-agent/api-guides/ruby-custom-instrumentation
    # https://rubydoc.info/github/newrelic/rpm/NewRelic/Agent/Tracer/
    NewRelic::Agent::Tracer.in_transaction(partial_name: "NewRelicInterceptor/#{method}", category: :web) do
      begin
        yield
      rescue GRPC::BadStatus => e
        NewRelic::Agent.add_custom_attributes({ grpc_response_status: e.code })
        raise
      end
    end
  end
end

main
