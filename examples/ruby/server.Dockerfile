FROM phusion/passenger-customizable:1.0.5

# Install Envoy
COPY --from=envoyproxy/envoy:v1.13.0 /usr/local/bin/envoy /usr/local/bin/envoy
COPY server_infra/docker/base/build/conf/envoy/envoy.yaml /etc/envoy/envoy.yaml

# Copy services
COPY server_infra/docker/base/build/service /etc/service

# Copy over runsv custom control to allow NGINX to gracefully shutdown on SIGTERM
COPY server_infra/docker/base/build/service/nginx /etc/service/nginx

# Add nginx config and prep to run as a service
COPY server_infra/docker/base/build/conf/nginx/nginx.conf /etc/nginx/sites-available/nginx.conf
RUN ln -s /etc/nginx/sites-available/nginx.conf /etc/nginx/sites-enabled/nginx.conf && \
  rm /etc/nginx/sites-enabled/default && \
  rm -f /etc/service/nginx/down

WORKDIR /home/app/greeter_server

COPY . .

RUN gem update --system
RUN gem install bundler
RUN bundle config --global silence_root_warning 1
RUN bundle install

# Configure my_init KILL grace period
ENV KILL_PROCESS_TIMEOUT=300

# LEAVE THIS COMMAND: it is used to start our monitoring/logging agents
CMD ["/sbin/my_init"]
